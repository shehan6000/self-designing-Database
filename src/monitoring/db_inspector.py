"""
Database State Inspector for Self-Designing Database
Captures indexes, table statistics, query plans, and configuration
"""

import json
import psycopg2
from psycopg2.extras import RealDictCursor
from datetime import datetime
from typing import Dict, List, Optional, Any, Tuple
import pandas as pd
import numpy as np
from dataclasses import dataclass, field, asdict
import hashlib
import logging

logger = logging.getLogger(__name__)

@dataclass
class IndexInfo:
    """Information about a database index"""
    index_name: str
    table_name: str
    schema_name: str
    index_type: str
    is_unique: bool
    is_primary: bool
    columns: List[str]
    index_size_bytes: int
    index_size_pretty: str
    index_scan_count: int
    index_tup_fetch: int
    index_tup_read: int
    last_used: Optional[datetime] = None
    creation_time: Optional[datetime] = None
    definition: Optional[str] = None
    
    @property
    def usage_ratio(self) -> float:
        """Calculate index usage ratio"""
        if self.index_scan_count == 0:
            return 0.0
        return self.index_tup_fetch / self.index_scan_count if self.index_scan_count > 0 else 0.0
    
    @property
    def efficiency(self) -> float:
        """Calculate index efficiency (fetches per scan)"""
        if self.index_scan_count == 0:
            return 0.0
        return self.index_tup_fetch / max(self.index_scan_count, 1)

@dataclass
class TableStats:
    """Table statistics"""
    schema_name: str
    table_name: str
    row_count: int
    table_size_bytes: int
    table_size_pretty: str
    index_size_bytes: int
    total_size_bytes: int
    total_size_pretty: str
    live_tuples: int
    dead_tuples: int
    dead_tuple_ratio: float
    last_vacuum: Optional[datetime]
    last_autovacuum: Optional[datetime]
    last_analyze: Optional[datetime]
    last_autoanalyze: Optional[datetime]
    sequential_scans: int
    sequential_tuples_read: int
    index_scans: int
    index_tuples_fetched: int
    inserts: int
    updates: int
    deletes: int
    hot_updates: int
    columns: List[Dict[str, Any]] = field(default_factory=list)
    indexes: List[IndexInfo] = field(default_factory=list)
    
    @property
    def bloat_factor(self) -> float:
        """Calculate table bloat factor"""
        if self.live_tuples == 0:
            return 0.0
        return self.dead_tuples / self.live_tuples
    
    @property
    def scan_efficiency(self) -> float:
        """Calculate scan efficiency (index scans vs sequential scans)"""
        total_scans = self.sequential_scans + self.index_scans
        if total_scans == 0:
            return 0.0
        return self.index_scans / total_scans

@dataclass
class QueryPlan:
    """Query execution plan analysis"""
    query_text: str
    query_id: str
    plan_id: str
    execution_time: float
    plan_type: str
    total_cost: float
    startup_cost: float
    plan_rows: int
    actual_rows: int
    actual_loops: int
    operations: List[Dict[str, Any]]
    nodes: List[Dict[str, Any]]
    buffers: Dict[str, int]
    timing: Dict[str, float]
    warnings: List[str] = field(default_factory=list)
    
    @property
    def plan_accuracy(self) -> float:
        """How accurate was the planner's row estimate?"""
        if self.plan_rows == 0:
            return 1.0 if self.actual_rows == 0 else 0.0
        return min(self.actual_rows / self.plan_rows, self.plan_rows / self.actual_rows)
    
    @property
    def efficiency_score(self) -> float:
        """Calculate plan efficiency score (0-1)"""
        # Lower is better for costs, higher is better for accuracy
        cost_score = 1.0 / (1.0 + self.total_cost / 1000.0)  # Normalize cost
        accuracy_score = self.plan_accuracy
        return (cost_score + accuracy_score) / 2.0

@dataclass
class DatabaseConfiguration:
    """Database configuration snapshot"""
    timestamp: datetime
    version: str
    settings: Dict[str, Any]
    extensions: List[Dict[str, Any]]
    roles: List[Dict[str, Any]]
    schemas: List[Dict[str, Any]]
    configuration_hash: str
    
    @classmethod
    def compute_hash(cls, settings: Dict[str, Any]) -> str:
        """Compute hash of configuration for change detection"""
        config_str = json.dumps(settings, sort_keys=True)
        return hashlib.sha256(config_str.encode()).hexdigest()

class DatabaseInspector:
    """Main database inspection class"""
    
    def __init__(self, connection_params: Dict[str, str]):
        self.connection_params = connection_params
        self.connection = None
        self.snapshots = []
        
    def connect(self):
        """Establish database connection"""
        self.connection = psycopg2.connect(
            **self.connection_params,
            cursor_factory=RealDictCursor
        )
        logger.info("Connected to database for inspection")
    
    def disconnect(self):
        """Close database connection"""
        if self.connection:
            self.connection.close()
            self.connection = None
    
    def get_all_indexes(self) -> List[IndexInfo]:
        """Retrieve all indexes with their statistics"""
        query = """
        SELECT
            schemaname,
            tablename,
            indexname,
            indexdef,
            indisunique,
            indisprimary,
            pg_relation_size(indexrelid) as index_size,
            idx_scan,
            idx_tup_read,
            idx_tup_fetch
        FROM pg_stat_user_indexes
        JOIN pg_indexes USING (schemaname, tablename, indexname)
        JOIN pg_index ON indexrelid = pg_stat_user_indexes.indexrelid
        ORDER BY schemaname, tablename, indexname
        """
        
        indexes = []
        try:
            with self.connection.cursor() as cursor:
                cursor.execute(query)
                for row in cursor.fetchall():
                    # Parse index columns from definition
                    definition = row['indexdef']
                    columns = self._extract_index_columns(definition)
                    
                    index = IndexInfo(
                        index_name=row['indexname'],
                        table_name=row['tablename'],
                        schema_name=row['schemaname'],
                        index_type=self._determine_index_type(definition),
                        is_unique=row['indisunique'],
                        is_primary=row['indisprimary'],
                        columns=columns,
                        index_size_bytes=row['index_size'] or 0,
                        index_size_pretty=self._format_bytes(row['index_size'] or 0),
                        index_scan_count=row['idx_scan'] or 0,
                        index_tup_fetch=row['idx_tup_fetch'] or 0,
                        index_tup_read=row['idx_tup_read'] or 0,
                        definition=definition
                    )
                    indexes.append(index)
        
        except Exception as e:
            logger.error(f"Error fetching indexes: {e}")
        
        return indexes
    
    def _extract_index_columns(self, index_def: str) -> List[str]:
        """Extract column names from index definition"""
        import re
        
        # Look for columns in parentheses
        match = re.search(r'\(([^)]+)\)', index_def)
        if match:
            columns_str = match.group(1)
            # Split by commas and clean up
            columns = [col.strip().split(' ')[0] for col in columns_str.split(',')]
            return columns
        
        return []
    
    def _determine_index_type(self, index_def: str) -> str:
        """Determine index type from definition"""
        if 'USING btree' in index_def or 'CREATE INDEX' in index_def and 'USING' not in index_def:
            return 'btree'
        elif 'USING hash' in index_def:
            return 'hash'
        elif 'USING gist' in index_def:
            return 'gist'
        elif 'USING gin' in index_def:
            return 'gin'
        elif 'USING brin' in index_def:
            return 'brin'
        elif 'USING spgist' in index_def:
            return 'spgist'
        else:
            return 'unknown'
    
    def get_table_statistics(self) -> List[TableStats]:
        """Retrieve detailed statistics for all tables"""
        # First get basic table stats
        query = """
        SELECT
            schemaname,
            relname,
            n_live_tup as live_tuples,
            n_dead_tup as dead_tuples,
            seq_scan as sequential_scans,
            seq_tup_read as sequential_tuples_read,
            idx_scan as index_scans,
            idx_tup_fetch as index_tuples_fetched,
            n_tup_ins as inserts,
            n_tup_upd as updates,
            n_tup_del as deletes,
            n_tup_hot_upd as hot_updates,
            last_vacuum,
            last_autovacuum,
            last_analyze,
            last_autoanalyze,
            pg_total_relation_size(relid) as total_size,
            pg_relation_size(relid) as table_size,
            pg_indexes_size(relid) as index_size
        FROM pg_stat_user_tables
        ORDER BY total_size DESC
        """
        
        tables = []
        try:
            with self.connection.cursor() as cursor:
                cursor.execute(query)
                for row in cursor.fetchall():
                    dead_ratio = row['dead_tuples'] / max(row['live_tuples'], 1)
                    
                    table = TableStats(
                        schema_name=row['schemaname'],
                        table_name=row['relname'],
                        row_count=row['live_tuples'],
                        table_size_bytes=row['table_size'] or 0,
                        table_size_pretty=self._format_bytes(row['table_size'] or 0),
                        index_size_bytes=row['index_size'] or 0,
                        total_size_bytes=row['total_size'] or 0,
                        total_size_pretty=self._format_bytes(row['total_size'] or 0),
                        live_tuples=row['live_tuples'],
                        dead_tuples=row['dead_tuples'],
                        dead_tuple_ratio=dead_ratio,
                        last_vacuum=row['last_vacuum'],
                        last_autovacuum=row['last_autovacuum'],
                        last_analyze=row['last_analyze'],
                        last_autoanalyze=row['last_autoanalyze'],
                        sequential_scans=row['sequential_scans'],
                        sequential_tuples_read=row['sequential_tuples_read'],
                        index_scans=row['index_scans'],
                        index_tuples_fetched=row['index_tuples_fetched'],
                        inserts=row['inserts'],
                        updates=row['updates'],
                        deletes=row['deletes'],
                        hot_updates=row['hot_updates']
                    )
                    
                    # Get column information
                    table.columns = self._get_table_columns(row['schemaname'], row['relname'])
                    
                    tables.append(table)
        
        except Exception as e:
            logger.error(f"Error fetching table statistics: {e}")
        
        return tables
    
    def _get_table_columns(self, schema: str, table: str) -> List[Dict[str, Any]]:
        """Get detailed column information for a table"""
        query = """
        SELECT
            column_name,
            data_type,
            is_nullable,
            column_default,
            character_maximum_length,
            numeric_precision,
            numeric_scale,
            ordinal_position
        FROM information_schema.columns
        WHERE table_schema = %s AND table_name = %s
        ORDER BY ordinal_position
        """
        
        try:
            with self.connection.cursor() as cursor:
                cursor.execute(query, (schema, table))
                return [dict(row) for row in cursor.fetchall()]
        except Exception as e:
            logger.error(f"Error fetching columns for {schema}.{table}: {e}")
            return []
    
    def analyze_query_plan(self, query: str, params: Optional[Tuple] = None) -> QueryPlan:
        """Analyze query execution plan"""
        plan_query = f"EXPLAIN (ANALYZE, BUFFERS, TIMING, VERBOSE, FORMAT JSON) {query}"
        
        try:
            with self.connection.cursor() as cursor:
                if params:
                    cursor.execute(plan_query, params)
                else:
                    cursor.execute(plan_query)
                
                result = cursor.fetchone()
                plan_data = result['QUERY PLAN'][0] if result else {}
                
                # Generate plan ID
                plan_id = hashlib.md5(f"{query}{params}".encode()).hexdigest()[:16]
                
                return self._parse_plan_data(query, plan_id, plan_data)
        
        except Exception as e:
            logger.error(f"Error analyzing query plan: {e}")
            return QueryPlan(
                query_text=query,
                query_id='',
                plan_id='error',
                execution_time=0.0,
                plan_type='error',
                total_cost=0.0,
                startup_cost=0.0,
                plan_rows=0,
                actual_rows=0,
                actual_loops=0,
                operations=[],
                nodes=[],
                buffers={},
                timing={},
                warnings=[str(e)]
            )
    
    def _parse_plan_data(self, query: str, plan_id: str, plan_data: Dict) -> QueryPlan:
        """Parse EXPLAIN output into QueryPlan object"""
        plan = plan_data.get('Plan', {})
        
        # Extract operations recursively
        operations = []
        nodes = []
        
        def extract_node(node: Dict, depth: int = 0):
            node_type = node.get('Node Type', 'Unknown')
            operations.append({
                'type': node_type,
                'relation_name': node.get('Relation Name'),
                'alias': node.get('Alias'),
                'startup_cost': node.get('Startup Cost', 0.0),
                'total_cost': node.get('Total Cost', 0.0),
                'plan_rows': node.get('Plan Rows', 0),
                'actual_rows': node.get('Actual Rows', 0),
                'actual_loops': node.get('Actual Loops', 1),
                'width': node.get('Plan Width', 0)
            })
            
            nodes.append({
                'node_type': node_type,
                'depth': depth,
                'cost': node.get('Total Cost', 0.0),
                'rows': node.get('Plan Rows', 0)
            })
            
            # Recursively process child nodes
            if 'Plans' in node:
                for child in node['Plans']:
                    extract_node(child, depth + 1)
        
        extract_node(plan)
        
        # Calculate query ID
        query_id = hashlib.md5(query.encode()).hexdigest()[:16]
        
        return QueryPlan(
            query_text=query,
            query_id=query_id,
            plan_id=plan_id,
            execution_time=plan_data.get('Execution Time', 0.0),
            plan_type=plan.get('Node Type', 'Unknown'),
            total_cost=plan.get('Total Cost', 0.0),
            startup_cost=plan.get('Startup Cost', 0.0),
            plan_rows=plan.get('Plan Rows', 0),
            actual_rows=plan.get('Actual Rows', 0),
            actual_loops=plan.get('Actual Loops', 1),
            operations=operations,
            nodes=nodes,
            buffers=plan_data.get('Buffers', {}),
            timing=plan_data.get('Timing', {})
        )
    
    def get_database_configuration(self) -> DatabaseConfiguration:
        """Get current database configuration"""
        queries = {
            'settings': """
                SELECT name, setting, unit, category, short_desc
                FROM pg_settings
                ORDER BY category, name
            """,
            'extensions': """
                SELECT extname, extversion, extrelocatable, extconfig
                FROM pg_extension
                ORDER BY extname
            """,
            'roles': """
                SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin
                FROM pg_roles
                WHERE rolname NOT LIKE 'pg_%'
                ORDER BY rolname
            """,
            'schemas': """
                SELECT schema_name
                FROM information_schema.schemata
                WHERE schema_name NOT IN ('pg_catalog', 'information_schema')
                ORDER BY schema_name
            """
        }
        
        config_data = {}
        for key, query in queries.items():
            try:
                with self.connection.cursor() as cursor:
                    cursor.execute(query)
                    config_data[key] = [dict(row) for row in cursor.fetchall()]
            except Exception as e:
                logger.error(f"Error fetching {key}: {e}")
                config_data[key] = []
        
        # Get version
        with self.connection.cursor() as cursor:
            cursor.execute("SELECT version()")
            version = cursor.fetchone()['version']
        
        # Compute configuration hash
        settings_dict = {s['name']: s['setting'] for s in config_data['settings']}
        config_hash = DatabaseConfiguration.compute_hash(settings_dict)
        
        return DatabaseConfiguration(
            timestamp=datetime.now(),
            version=version,
            settings=settings_dict,
            extensions=config_data['extensions'],
            roles=config_data['roles'],
            schemas=config_data['schemas'],
            configuration_hash=config_hash
        )
    
    def create_snapshot(self, name: Optional[str] = None) -> Dict[str, Any]:
        """Create a complete database snapshot"""
        if not name:
            name = f"snapshot_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        snapshot = {
            'name': name,
            'timestamp': datetime.now().isoformat(),
            'indexes': [asdict(idx) for idx in self.get_all_indexes()],
            'tables': [asdict(table) for table in self.get_table_statistics()],
            'configuration': asdict(self.get_database_configuration()),
            'summary': self._generate_snapshot_summary()
        }
        
        self.snapshots.append(snapshot)
        logger.info(f"Created snapshot: {name}")
        return snapshot
    
    def _generate_snapshot_summary(self) -> Dict[str, Any]:
        """Generate summary statistics for snapshot"""
        indexes = self.get_all_indexes()
        tables = self.get_table_statistics()
        
        total_index_size = sum(idx.index_size_bytes for idx in indexes)
        total_table_size = sum(table.total_size_bytes for table in tables)
        
        # Calculate index usage
        used_indexes = [idx for idx in indexes if idx.index_scan_count > 0]
        unused_indexes = [idx for idx in indexes if idx.index_scan_count == 0]
        
        return {
            'total_tables': len(tables),
            'total_indexes': len(indexes),
            'used_indexes': len(used_indexes),
            'unused_indexes': len(unused_indexes),
            'total_database_size': total_table_size,
            'total_index_size': total_index_size,
            'index_coverage': len(indexes) / max(len(tables), 1),
            'average_table_size': total_table_size / max(len(tables), 1),
            'average_index_size': total_index_size / max(len(indexes), 1),
            'unused_index_size': sum(idx.index_size_bytes for idx in unused_indexes)
        }
    
    def export_snapshot(self, snapshot: Dict, format: str = 'json') -> str:
        """Export snapshot in specified format"""
        if format == 'json':
            return json.dumps(snapshot, indent=2, default=str)
        elif format == 'csv':
            # Export tables to CSV
            tables_df = pd.DataFrame(snapshot['tables'])
            indexes_df = pd.DataFrame(snapshot['indexes'])
            
            return {
                'tables': tables_df.to_csv(index=False),
                'indexes': indexes_df.to_csv(index=False)
            }
        else:
            raise ValueError(f"Unsupported format: {format}")
    
    def compare_snapshots(self, snapshot1: Dict, snapshot2: Dict) -> Dict[str, Any]:
        """Compare two snapshots and highlight differences"""
        differences = {
            'added_indexes': [],
            'removed_indexes': [],
            'changed_indexes': [],
            'table_changes': [],
            'configuration_changes': []
        }
        
        # Compare indexes
        idx1_names = {idx['index_name']: idx for idx in snapshot1['indexes']}
        idx2_names = {idx['index_name']: idx for idx in snapshot2['indexes']}
        
        differences['added_indexes'] = [
            idx for name, idx in idx2_names.items() 
            if name not in idx1_names
        ]
        
        differences['removed_indexes'] = [
            idx for name, idx in idx1_names.items() 
            if name not in idx2_names
        ]
        
        # Find changed indexes
        for name, idx2 in idx2_names.items():
            if name in idx1_names:
                idx1 = idx1_names[name]
                if idx1 != idx2:
                    differences['changed_indexes'].append({
                        'index': name,
                        'before': idx1,
                        'after': idx2
                    })
        
        # Compare configurations
        if (snapshot1['configuration']['configuration_hash'] != 
            snapshot2['configuration']['configuration_hash']):
            differences['configuration_changes'] = self._compare_configurations(
                snapshot1['configuration']['settings'],
                snapshot2['configuration']['settings']
            )
        
        return differences
    
    def _compare_configurations(self, config1: Dict, config2: Dict) -> List[Dict[str, Any]]:
        """Compare two configuration dictionaries"""
        changes = []
        all_keys = set(config1.keys()) | set(config2.keys())
        
        for key in all_keys:
            val1 = config1.get(key)
            val2 = config2.get(key)
            
            if val1 != val2:
                changes.append({
                    'parameter': key,
                    'before': val1,
                    'after': val2,
                    'changed': val1 != val2
                })
        
        return changes
    
    @staticmethod
    def _format_bytes(bytes: int) -> str:
        """Format bytes to human readable string"""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes < 1024.0:
                return f"{bytes:.2f} {unit}"
            bytes /= 1024.0
        return f"{bytes:.2f} PB"

# Utility functions
def inspect_database(connection_params: Dict[str, str]) -> DatabaseInspector:
    """Create and return a database inspector"""
    inspector = DatabaseInspector(connection_params)
    inspector.connect()
    return inspector

def create_snapshot_and_export(
    connection_params: Dict[str, str],
    output_file: str,
    format: str = 'json'
):
    """Convenience function to create and export a snapshot"""
    inspector = inspect_database(connection_params)
    snapshot = inspector.create_snapshot()
    exported = inspector.export_snapshot(snapshot, format)
    
    if format == 'json':
        with open(output_file, 'w') as f:
            f.write(exported)
    elif format == 'csv':
        for file_type, content in exported.items():
            with open(f"{output_file}_{file_type}.csv", 'w') as f:
                f.write(content)
    
    inspector.disconnect()
    logger.info(f"Snapshot exported to {output_file}")

if __name__ == "__main__":
    # Example usage
    import json
    
    connection_params = {
        'host': 'localhost',
        'port': 5432,
        'database': 'self_designing_db',
        'user': 'admin',
        'password': 'admin123'
    }
    
    inspector = inspect_database(connection_params)
    
    # Create a snapshot
    snapshot = inspector.create_snapshot()
    print(json.dumps(snapshot['summary'], indent=2))
    
    # Get all indexes
    indexes = inspector.get_all_indexes()
    print(f"\nFound {len(indexes)} indexes")
    
    # Get table statistics
    tables = inspector.get_table_statistics()
    print(f"Found {len(tables)} tables")
    
    inspector.disconnect()
