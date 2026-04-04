"""
Workload Monitoring System for Self-Designing Database
Continuously monitors pg_stat_statements and extracts performance metrics
"""

import asyncio
import logging
import time
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Any
import psycopg2
from psycopg2.extras import RealDictCursor
import pandas as pd
import numpy as np
from dataclasses import dataclass, field
from collections import defaultdict, deque
import json
from prometheus_client import start_http_server, Gauge, Counter, Histogram, Summary

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class QueryMetrics:
    """Container for query performance metrics"""
    query_id: str
    query_text: str
    calls: int = 0
    total_time: float = 0.0
    mean_time: float = 0.0
    min_time: float = float('inf')
    max_time: float = 0.0
    rows: int = 0
    shared_blks_hit: int = 0
    shared_blks_read: int = 0
    temp_blks_read: int = 0
    temp_blks_written: int = 0
    last_executed: Optional[datetime] = None
    execution_history: deque = field(default_factory=lambda: deque(maxlen=100))
    
    @property
    def cache_hit_ratio(self) -> float:
        if self.shared_blks_hit + self.shared_blks_read == 0:
            return 0.0
        return self.shared_blks_hit / (self.shared_blks_hit + self.shared_blks_read)
    
    @property
    def throughput(self) -> float:
        if self.total_time == 0:
            return 0.0
        return self.rows / self.total_time

@dataclass
class TableAccessPattern:
    """Container for table access pattern analysis"""
    table_name: str
    total_accesses: int = 0
    sequential_scans: int = 0
    index_scans: int = 0
    inserts: int = 0
    updates: int = 0
    deletes: int = 0
    hot_rows: Dict[str, int] = field(default_factory=dict)
    access_times: List[datetime] = field(default_factory=list)

class WorkloadMonitor:
    """Main workload monitoring class"""
    
    def __init__(self, db_config: Dict[str, str], poll_interval: int = 30):
        """
        Initialize the workload monitor
        
        Args:
            db_config: Database connection parameters
            poll_interval: Polling interval in seconds
        """
        self.db_config = db_config
        self.poll_interval = poll_interval
        self.running = False
        self.connection = None
        
        # Metrics storage
        self.query_metrics: Dict[str, QueryMetrics] = {}
        self.table_patterns: Dict[str, TableAccessPattern] = {}
        self.workload_history: List[Dict] = []
        
        # Temporal analysis
        self.hourly_patterns: Dict[int, Dict] = defaultdict(lambda: {
            'query_count': 0,
            'total_time': 0.0,
            'read_queries': 0,
            'write_queries': 0
        })
        
        # Prometheus metrics
        self._init_prometheus_metrics()
        
    def _init_prometheus_metrics(self):
        """Initialize Prometheus metrics"""
        # Query metrics
        self.query_total_time = Gauge(
            'postgres_query_total_time_seconds',
            'Total execution time of queries',
            ['query_id', 'query_type']
        )
        self.query_mean_time = Gauge(
            'postgres_query_mean_time_seconds',
            'Mean execution time of queries',
            ['query_id']
        )
        self.query_calls = Counter(
            'postgres_query_calls_total',
            'Total number of query calls',
            ['query_id', 'query_type']
        )
        self.query_rows = Gauge(
            'postgres_query_rows',
            'Number of rows affected by query',
            ['query_id']
        )
        self.query_cache_hit_ratio = Gauge(
            'postgres_query_cache_hit_ratio',
            'Buffer cache hit ratio for query',
            ['query_id']
        )
        
        # Database-wide metrics
        self.db_connections = Gauge(
            'postgres_connections_total',
            'Total number of database connections'
        )
        self.db_transactions = Counter(
            'postgres_transactions_total',
            'Total number of transactions'
        )
        self.db_cache_hit_ratio = Gauge(
            'postgres_cache_hit_ratio',
            'Overall buffer cache hit ratio'
        )
        
        # Workload metrics
        self.workload_qps = Gauge(
            'postgres_queries_per_second',
            'Queries per second'
        )
        self.workload_read_write_ratio = Gauge(
            'postgres_read_write_ratio',
            'Ratio of read to write queries'
        )
        
    async def connect(self):
        """Establish database connection"""
        try:
            self.connection = psycopg2.connect(
                host=self.db_config.get('host', 'localhost'),
                port=self.db_config.get('port', 5432),
                database=self.db_config.get('database', 'self_designing_db'),
                user=self.db_config.get('user', 'admin'),
                password=self.db_config.get('password', 'admin123'),
                cursor_factory=RealDictCursor
            )
            logger.info("Connected to database")
        except Exception as e:
            logger.error(f"Failed to connect to database: {e}")
            raise
    
    async def fetch_query_statistics(self) -> List[Dict]:
        """Fetch query statistics from pg_stat_statements"""
        query = """
        SELECT 
            queryid,
            query,
            calls,
            total_exec_time as total_time,
            mean_exec_time as mean_time,
            min_exec_time as min_time,
            max_exec_time as max_time,
            rows,
            shared_blks_hit,
            shared_blks_read,
            temp_blks_read,
            temp_blks_written,
            blk_read_time,
            blk_write_time
        FROM pg_stat_statements
        WHERE query !~* '^pg_stat_statements'
        ORDER BY total_exec_time DESC
        LIMIT 100
        """
        
        try:
            with self.connection.cursor() as cursor:
                cursor.execute(query)
                results = cursor.fetchall()
                return [dict(row) for row in results]
        except Exception as e:
            logger.error(f"Error fetching query statistics: {e}")
            return []
    
    def analyze_query_type(self, query_text: str) -> Dict[str, Any]:
        """Analyze query type and extract patterns"""
        query_text_lower = query_text.lower().strip()
        
        analysis = {
            'type': 'unknown',
            'tables': [],
            'joins': 0,
            'filters': 0,
            'is_select': False,
            'is_insert': False,
            'is_update': False,
            'is_delete': False,
            'has_where': False,
            'has_order_by': False,
            'has_group_by': False,
            'has_limit': False
        }
        
        # Determine query type
        if query_text_lower.startswith('select'):
            analysis['type'] = 'select'
            analysis['is_select'] = True
        elif query_text_lower.startswith('insert'):
            analysis['type'] = 'insert'
            analysis['is_insert'] = True
        elif query_text_lower.startswith('update'):
            analysis['type'] = 'update'
            analysis['is_update'] = True
        elif query_text_lower.startswith('delete'):
            analysis['type'] = 'delete'
            analysis['is_delete'] = True
        
        # Extract table names (simplified)
        import re
        table_patterns = [
            r'from\s+(\w+)',
            r'join\s+(\w+)',
            r'update\s+(\w+)',
            r'into\s+(\w+)'
        ]
        
        for pattern in table_patterns:
            matches = re.findall(pattern, query_text_lower, re.IGNORECASE)
            analysis['tables'].extend(matches)
        
        # Count joins
        analysis['joins'] = len(re.findall(r'\s+join\s+', query_text_lower, re.IGNORECASE))
        
        # Check for clauses
        analysis['has_where'] = 'where' in query_text_lower
        analysis['has_order_by'] = 'order by' in query_text_lower
        analysis['has_group_by'] = 'group by' in query_text_lower
        analysis['has_limit'] = 'limit' in query_text_lower
        
        return analysis
    
    def update_query_metrics(self, stats: List[Dict]):
        """Update query metrics from fetched statistics"""
        current_time = datetime.now()
        
        for stat in stats:
            query_id = str(stat['queryid'])
            query_text = stat['query']
            
            if query_id not in self.query_metrics:
                self.query_metrics[query_id] = QueryMetrics(
                    query_id=query_id,
                    query_text=query_text
                )
            
            metrics = self.query_metrics[query_id]
            metrics.calls = stat['calls']
            metrics.total_time = stat['total_time']
            metrics.mean_time = stat['mean_time']
            metrics.min_time = min(metrics.min_time, stat.get('min_time', metrics.mean_time))
            metrics.max_time = max(metrics.max_time, stat.get('max_time', metrics.mean_time))
            metrics.rows = stat['rows']
            metrics.shared_blks_hit = stat['shared_blks_hit']
            metrics.shared_blks_read = stat['shared_blks_read']
            metrics.last_executed = current_time
            
            # Add to execution history
            metrics.execution_history.append({
                'timestamp': current_time,
                'execution_time': metrics.mean_time,
                'rows': metrics.rows
            })
            
            # Update Prometheus metrics
            query_analysis = self.analyze_query_type(query_text)
            query_type = query_analysis['type']
            
            self.query_total_time.labels(
                query_id=query_id,
                query_type=query_type
            ).set(metrics.total_time)
            
            self.query_mean_time.labels(
                query_id=query_id
            ).set(metrics.mean_time)
            
            self.query_calls.labels(
                query_id=query_id,
                query_type=query_type
            ).inc(metrics.calls)
            
            self.query_rows.labels(
                query_id=query_id
            ).set(metrics.rows)
            
            self.query_cache_hit_ratio.labels(
                query_id=query_id
            ).set(metrics.cache_hit_ratio)
    
    async def fetch_table_statistics(self):
        """Fetch table access statistics"""
        query = """
        SELECT 
            schemaname,
            relname,
            seq_scan,
            seq_tup_read,
            idx_scan,
            idx_tup_fetch,
            n_tup_ins,
            n_tup_upd,
            n_tup_del,
            n_live_tup,
            n_dead_tup
        FROM pg_stat_user_tables
        ORDER BY seq_scan + idx_scan DESC
        """
        
        try:
            with self.connection.cursor() as cursor:
                cursor.execute(query)
                results = cursor.fetchall()
                
                for row in results:
                    table_name = f"{row['schemaname']}.{row['relname']}"
                    
                    if table_name not in self.table_patterns:
                        self.table_patterns[table_name] = TableAccessPattern(
                            table_name=table_name
                        )
                    
                    pattern = self.table_patterns[table_name]
                    pattern.sequential_scans = row['seq_scan']
                    pattern.index_scans = row['idx_scan']
                    pattern.inserts = row['n_tup_ins']
                    pattern.updates = row['n_tup_upd']
                    pattern.deletes = row['n_tup_del']
                    pattern.total_accesses = (
                        pattern.sequential_scans + 
                        pattern.index_scans +
                        pattern.inserts +
                        pattern.updates +
                        pattern.deletes
                    )
                    
                    # Record access time
                    pattern.access_times.append(datetime.now())
                    
        except Exception as e:
            logger.error(f"Error fetching table statistics: {e}")
    
    async def fetch_database_metrics(self) -> Dict[str, Any]:
        """Fetch database-wide metrics"""
        queries = {
            'connections': """
                SELECT COUNT(*) as count, state 
                FROM pg_stat_activity 
                WHERE datname = current_database()
                GROUP BY state
            """,
            'cache': """
                SELECT 
                    sum(heap_blks_hit) / 
                    nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0) 
                    as hit_ratio
                FROM pg_statio_user_tables
            """,
            'transactions': """
                SELECT 
                    xact_commit as commits,
                    xact_rollback as rollbacks
                FROM pg_stat_database 
                WHERE datname = current_database()
            """
        }
        
        metrics = {}
        for name, query in queries.items():
            try:
                with self.connection.cursor() as cursor:
                    cursor.execute(query)
                    result = cursor.fetchone()
                    metrics[name] = dict(result) if result else {}
            except Exception as e:
                logger.error(f"Error fetching {name} metrics: {e}")
                metrics[name] = {}
        
        return metrics
    
    def analyze_temporal_patterns(self):
        """Analyze workload patterns over time"""
        current_hour = datetime.now().hour
        
        # Update hourly patterns
        total_queries = len(self.query_metrics)
        total_time = sum(m.total_time for m in self.query_metrics.values())
        
        read_queries = sum(1 for m in self.query_metrics.values() 
                          if m.query_text.lower().startswith('select'))
        write_queries = total_queries - read_queries
        
        self.hourly_patterns[current_hour]['query_count'] += total_queries
        self.hourly_patterns[current_hour]['total_time'] += total_time
        self.hourly_patterns[current_hour]['read_queries'] += read_queries
        self.hourly_patterns[current_hour]['write_queries'] += write_queries
        
        # Calculate QPS
        if len(self.workload_history) > 1:
            last_metrics = self.workload_history[-1]
            time_diff = (datetime.now() - last_metrics['timestamp']).total_seconds()
            if time_diff > 0:
                qps = total_queries / time_diff
                self.workload_qps.set(qps)
                
                # Update read/write ratio
                if write_queries > 0:
                    ratio = read_queries / write_queries
                    self.workload_read_write_ratio.set(ratio)
    
    async def monitor_loop(self):
        """Main monitoring loop"""
        logger.info("Starting workload monitor")
        self.running = True
        
        # Start Prometheus metrics server
        start_http_server(8000)
        
        while self.running:
            try:
                # Fetch and update metrics
                query_stats = await self.fetch_query_statistics()
                self.update_query_metrics(query_stats)
                
                await self.fetch_table_statistics()
                
                db_metrics = await self.fetch_database_metrics()
                
                # Update Prometheus metrics
                if 'connections' in db_metrics:
                    total_connections = sum(
                        c['count'] for c in db_metrics['connections'] 
                        if isinstance(db_metrics['connections'], list)
                    )
                    self.db_connections.set(total_connections)
                
                if 'cache' in db_metrics and db_metrics['cache'].get('hit_ratio'):
                    self.db_cache_hit_ratio.set(db_metrics['cache']['hit_ratio'])
                
                # Analyze temporal patterns
                self.analyze_temporal_patterns()
                
                # Store in history
                self.workload_history.append({
                    'timestamp': datetime.now(),
                    'query_count': len(query_stats),
                    'total_time': sum(s['total_time'] for s in query_stats),
                    'db_metrics': db_metrics
                })
                
                # Keep history manageable
                if len(self.workload_history) > 1000:
                    self.workload_history = self.workload_history[-1000:]
                
                logger.debug(f"Monitored {len(query_stats)} queries")
                
            except Exception as e:
                logger.error(f"Error in monitoring loop: {e}")
            
            await asyncio.sleep(self.poll_interval)
    
    async def stop(self):
        """Stop the monitoring loop"""
        self.running = False
        if self.connection:
            self.connection.close()
        logger.info("Workload monitor stopped")
    
    def get_workload_summary(self) -> Dict[str, Any]:
        """Get a summary of the current workload"""
        total_queries = len(self.query_metrics)
        total_time = sum(m.total_time for m in self.query_metrics.values())
        
        # Categorize queries
        query_types = defaultdict(int)
        for metrics in self.query_metrics.values():
            analysis = self.analyze_query_type(metrics.query_text)
            query_types[analysis['type']] += 1
        
        # Get top tables
        top_tables = sorted(
            self.table_patterns.items(),
            key=lambda x: x[1].total_accesses,
            reverse=True
        )[:10]
        
        # Calculate percentiles
        execution_times = [m.mean_time for m in self.query_metrics.values()]
        percentiles = {
            'p50': np.percentile(execution_times, 50) if execution_times else 0,
            'p95': np.percentile(execution_times, 95) if execution_times else 0,
            'p99': np.percentile(execution_times, 99) if execution_times else 0
        }
        
        return {
            'timestamp': datetime.now().isoformat(),
            'total_queries': total_queries,
            'total_execution_time': total_time,
            'average_query_time': total_time / total_queries if total_queries > 0 else 0,
            'query_type_distribution': dict(query_types),
            'top_tables': [
                {
                    'table': table,
                    'accesses': pattern.total_accesses,
                    'sequential_scans': pattern.sequential_scans,
                    'index_scans': pattern.index_scans
                }
                for table, pattern in top_tables
            ],
            'performance_metrics': {
                'latency_percentiles': percentiles,
                'cache_hit_ratio_avg': np.mean([
                    m.cache_hit_ratio for m in self.query_metrics.values()
                ]) if self.query_metrics else 0,
                'throughput_avg': np.mean([
                    m.throughput for m in self.query_metrics.values()
                ]) if self.query_metrics else 0
            },
            'temporal_patterns': {
                hour: dict(pattern)
                for hour, pattern in self.hourly_patterns.items()
            }
        }
    
    def export_metrics(self, format: str = 'json') -> str:
        """Export metrics in specified format"""
        summary = self.get_workload_summary()
        
        if format == 'json':
            return json.dumps(summary, indent=2, default=str)
        elif format == 'prometheus':
            # Convert to Prometheus exposition format
            lines = []
            for query_id, metrics in self.query_metrics.items():
                lines.append(f'postgres_query_execution_time_seconds{{query_id="{query_id}"}} {metrics.mean_time}')
                lines.append(f'postgres_query_calls_total{{query_id="{query_id}"}} {metrics.calls}')
                lines.append(f'postgres_query_rows_total{{query_id="{query_id}"}} {metrics.rows}')
                lines.append(f'postgres_query_cache_hit_ratio{{query_id="{query_id}"}} {metrics.cache_hit_ratio}')
            
            return '\n'.join(lines)
        else:
            raise ValueError(f"Unsupported format: {format}")

# Singleton instance
_workload_monitor = None

def get_workload_monitor(db_config: Optional[Dict] = None) -> WorkloadMonitor:
    """Get or create a workload monitor instance"""
    global _workload_monitor
    
    if _workload_monitor is None:
        if db_config is None:
            db_config = {
                'host': 'localhost',
                'port': 5432,
                'database': 'self_designing_db',
                'user': 'admin',
                'password': 'admin123'
            }
        _workload_monitor = WorkloadMonitor(db_config)
    
    return _workload_monitor

async def start_monitoring(db_config: Optional[Dict] = None, poll_interval: int = 30):
    """Start the monitoring system"""
    monitor = get_workload_monitor(db_config)
    await monitor.connect()
    await monitor.monitor_loop()

if __name__ == "__main__":
    # Example usage
    import asyncio
    
    async def main():
        monitor = WorkloadMonitor({
            'host': 'localhost',
            'port': 5432,
            'database': 'self_designing_db',
            'user': 'admin',
            'password': 'admin123'
        })
        
        try:
            await monitor.connect()
            await monitor.monitor_loop()
        except KeyboardInterrupt:
            await monitor.stop()
    
    asyncio.run(main())
