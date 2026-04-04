"""
Feature Extraction Pipeline for Self-Designing Database
Converts raw metrics to RL state vectors
"""

import numpy as np
import pandas as pd
from typing import Dict, List, Tuple, Any, Optional
from dataclasses import dataclass, field
import json
from datetime import datetime
import logging
from sklearn.preprocessing import StandardScaler, MinMaxScaler
from sklearn.feature_extraction import DictVectorizer
import hashlib

logger = logging.getLogger(__name__)

@dataclass
class WorkloadFeatures:
    """Workload-related features"""
    # Query distribution features
    query_type_distribution: Dict[str, float]  # SELECT, INSERT, UPDATE, DELETE percentages
    query_complexity_features: Dict[str, float]  # Joins, filters, sorts per query
    
    # Temporal features
    hourly_pattern: List[float]  # 24-hour pattern
    minute_of_hour: float  # Current minute
    day_of_week: float  # Current day
    
    # Access pattern features
    table_access_frequency: Dict[str, float]  # Normalized access counts per table
    index_usage_pattern: Dict[str, float]  # Index usage ratios
    
    # Performance features
    latency_percentiles: Dict[str, float]  # p50, p95, p99
    throughput: float  # Queries per second
    cache_hit_ratio: float  # Overall cache hit ratio
    
    # Resource usage
    connections_ratio: float  # Current connections / max connections
    lock_wait_ratio: float  # Lock wait time / total time

@dataclass
class ConfigurationFeatures:
    """Database configuration features"""
    # Index features
    index_count: int
    index_coverage: float  # Indexes per table
    index_size_ratio: float  # Index size / table size
    index_usage_distribution: Dict[str, float]  # Usage patterns
    
    # Table features
    table_count: int
    average_table_size: float
    table_bloat_factor: float  # Dead tuples / live tuples
    
    # Schema features
    column_statistics: Dict[str, float]  # Average columns per table, data type distribution
    partitioning_status: Dict[str, float]  # Partitioned tables ratio
    
    # Configuration parameters
    memory_settings: Dict[str, float]  # shared_buffers, work_mem, etc.
    checkpoint_settings: Dict[str, float]  # checkpoint parameters

@dataclass
class PerformanceFeatures:
    """Performance metric features"""
    # Latency features (normalized)
    query_latency_stats: Dict[str, float]  # mean, std, min, max
    transaction_latency: float
    
    # Throughput features
    read_throughput: float  # Reads per second
    write_throughput: float  # Writes per second
    total_throughput: float
    
    # Resource efficiency
    cpu_utilization: float
    memory_utilization: float
    disk_io_utilization: float
    
    # Quality metrics
    error_rate: float
    timeout_rate: float
    replication_lag: float

class FeatureExtractor:
    """Main feature extraction class"""
    
    def __init__(self, 
                 normalize: bool = True,
                 include_temporal: bool = True,
                 feature_dim: int = 256):
        """
        Initialize feature extractor
        
        Args:
            normalize: Whether to normalize features
            include_temporal: Whether to include temporal features
            feature_dim: Target feature dimension
        """
        self.normalize = normalize
        self.include_temporal = include_temporal
        self.feature_dim = feature_dim
        
        # Scalers for normalization
        self.scalers = {}
        self.vectorizers = {}
        
        # Feature cache for efficiency
        self.feature_cache = {}
        self.cache_size = 1000
        
        # Initialize feature dimensions
        self._init_feature_dimensions()
    
    def _init_feature_dimensions(self):
        """Initialize feature dimension mappings"""
        # Workload features dimensions
        self.workload_dims = {
            'query_type': 4,  # SELECT, INSERT, UPDATE, DELETE
            'temporal': 26,   # 24h + minute + day
            'access_pattern': 50,  # Top 50 tables
            'performance': 10,  # Latency percentiles + throughput + cache
            'resource': 2,     # Connections + locks
        }
        
        # Configuration features dimensions
        self.config_dims = {
            'index': 50,       # Index statistics
            'table': 20,       # Table statistics
            'schema': 30,      # Schema statistics
            'settings': 20,    # Configuration settings
        }
        
        # Performance features dimensions
        self.performance_dims = {
            'latency': 10,     # Latency statistics
            'throughput': 3,   # Read/write/total
            'resource': 3,     # CPU/memory/disk
            'quality': 3,      # Error/timeout/lag
        }
    
    def extract_state_vector(self, 
                            workload_data: Dict[str, Any],
                            config_data: Dict[str, Any],
                            performance_data: Dict[str, Any]) -> np.ndarray:
        """
        Extract complete state vector from raw data
        
        Args:
            workload_data: Raw workload monitoring data
            config_data: Database configuration data
            performance_data: Performance metrics
            
        Returns:
            Normalized state vector as numpy array
        """
        # Generate cache key
        cache_key = self._generate_cache_key(workload_data, config_data, performance_data)
        
        # Check cache
        if cache_key in self.feature_cache:
            return self.feature_cache[cache_key]
        
        # Extract individual feature sets
        workload_features = self._extract_workload_features(workload_data)
        config_features = self._extract_configuration_features(config_data)
        performance_features = self._extract_performance_features(performance_data)
        
        # Convert to vectors
        workload_vector = self._workload_to_vector(workload_features)
        config_vector = self._configuration_to_vector(config_features)
        performance_vector = self._performance_to_vector(performance_features)
        
        # Concatenate vectors
        state_vector = np.concatenate([
            workload_vector,
            config_vector,
            performance_vector
        ])
        
        # Pad or truncate to target dimension
        state_vector = self._adjust_dimension(state_vector)
        
        # Normalize if enabled
        if self.normalize:
            state_vector = self._normalize_vector(state_vector)
        
        # Cache result
        self._add_to_cache(cache_key, state_vector)
        
        return state_vector
    
    def _generate_cache_key(self, *data_dicts: Dict) -> str:
        """Generate cache key from data dictionaries"""
        combined = json.dumps(data_dicts, sort_keys=True, default=str)
        return hashlib.md5(combined.encode()).hexdigest()
    
    def _add_to_cache(self, key: str, vector: np.ndarray):
        """Add vector to cache"""
        if len(self.feature_cache) >= self.cache_size:
            # Remove oldest entry (FIFO)
            oldest_key = next(iter(self.feature_cache))
            del self.feature_cache[oldest_key]
        
        self.feature_cache[key] = vector
    
    def _extract_workload_features(self, workload_data: Dict) -> WorkloadFeatures:
        """Extract workload features from raw data"""
        # Query type distribution
        query_type_dist = workload_data.get('query_type_distribution', {})
        total_queries = sum(query_type_dist.values())
        
        normalized_query_dist = {
            'select': query_type_dist.get('select', 0) / max(total_queries, 1),
            'insert': query_type_dist.get('insert', 0) / max(total_queries, 1),
            'update': query_type_dist.get('update', 0) / max(total_queries, 1),
            'delete': query_type_dist.get('delete', 0) / max(total_queries, 1)
        }
        
        # Temporal features
        current_time = datetime.now()
        hourly_pattern = [0.0] * 24
        hour = current_time.hour
        
        # Update hourly pattern from history if available
        if 'temporal_patterns' in workload_data:
            for h, pattern in workload_data['temporal_patterns'].items():
                if 0 <= h < 24:
                    hourly_pattern[h] = pattern.get('query_count', 0) / max(pattern.get('total_time', 1), 1)
        
        # Normalize hourly pattern
        max_hourly = max(hourly_pattern) if hourly_pattern else 1.0
        if max_hourly > 0:
            hourly_pattern = [h / max_hourly for h in hourly_pattern]
        
        # Access pattern features
        table_access_freq = {}
        if 'top_tables' in workload_data:
            top_tables = workload_data['top_tables'][:50]  # Top 50 tables
            total_accesses = sum(t['accesses'] for t in top_tables)
            
            for table_info in top_tables:
                table_name = table_info['table']
                accesses = table_info['accesses']
                table_access_freq[table_name] = accesses / max(total_accesses, 1)
        
        # Performance features
        perf_metrics = workload_data.get('performance_metrics', {})
        latency_percentiles = perf_metrics.get('latency_percentiles', {})
        
        return WorkloadFeatures(
            query_type_distribution=normalized_query_dist,
            query_complexity_features=self._extract_query_complexity(workload_data),
            hourly_pattern=hourly_pattern,
            minute_of_hour=current_time.minute / 60.0,
            day_of_week=current_time.weekday() / 7.0,
            table_access_frequency=table_access_freq,
            index_usage_pattern=self._extract_index_usage(workload_data),
            latency_percentiles={
                'p50': latency_percentiles.get('p50', 0),
                'p95': latency_percentiles.get('p95', 0),
                'p99': latency_percentiles.get('p99', 0)
            },
            throughput=perf_metrics.get('throughput_avg', 0),
            cache_hit_ratio=perf_metrics.get('cache_hit_ratio_avg', 0),
            connections_ratio=workload_data.get('connections_ratio', 0),
            lock_wait_ratio=workload_data.get('lock_wait_ratio', 0)
        )
    
    def _extract_query_complexity(self, workload_data: Dict) -> Dict[str, float]:
        """Extract query complexity features"""
        # This would typically analyze query patterns
        # For now, return placeholder features
        return {
            'avg_joins': 1.5,
            'avg_filters': 3.2,
            'avg_sorts': 0.8,
            'avg_subqueries': 0.3,
            'avg_ctes': 0.1
        }
    
    def _extract_index_usage(self, workload_data: Dict) -> Dict[str, float]:
        """Extract index usage patterns"""
        # This would analyze index usage from pg_stat_user_indexes
        # For now, return placeholder
        return {
            'btree_usage': 0.85,
            'gin_usage': 0.10,
            'gist_usage': 0.03,
            'hash_usage': 0.01,
            'brin_usage': 0.01
        }
    
    def _extract_configuration_features(self, config_data: Dict) -> ConfigurationFeatures:
        """Extract configuration features from raw data"""
        summary = config_data.get('summary', {})
        
        # Index features
        index_count = summary.get('total_indexes', 0)
        table_count = summary.get('total_tables', 1)
        index_coverage = index_count / table_count
        
        total_index_size = summary.get('total_index_size', 0)
        total_db_size = summary.get('total_database_size', 1)
        index_size_ratio = total_index_size / total_db_size
        
        # Index usage distribution
        used_indexes = summary.get('used_indexes', 0)
        unused_indexes = summary.get('unused_indexes', 0)
        total_indexes = used_indexes + unused_indexes
        
        index_usage_dist = {
            'used_ratio': used_indexes / max(total_indexes, 1),
            'unused_ratio': unused_indexes / max(total_indexes, 1),
            'efficiency': summary.get('index_efficiency', 0.5)
        }
        
        # Table features
        avg_table_size = summary.get('average_table_size', 0)
        bloat_factor = 0.0  # Would calculate from table stats
        
        # Schema features
        column_stats = self._extract_column_statistics(config_data)
        partitioning_status = self._extract_partitioning_status(config_data)
        
        # Configuration settings
        settings = config_data.get('configuration', {}).get('settings', {})
        memory_settings = {
            'shared_buffers': float(settings.get('shared_buffers', '128MB').replace('MB', '')) / 1024,
            'work_mem': float(settings.get('work_mem', '4MB').replace('MB', '')) / 1024,
            'maintenance_work_mem': float(settings.get('maintenance_work_mem', '64MB').replace('MB', '')) / 1024
        }
        
        checkpoint_settings = {
            'checkpoint_timeout': float(settings.get('checkpoint_timeout', '300')),
            'checkpoint_completion_target': float(settings.get('checkpoint_completion_target', '0.9'))
        }
        
        return ConfigurationFeatures(
            index_count=index_count,
            index_coverage=index_coverage,
            index_size_ratio=index_size_ratio,
            index_usage_distribution=index_usage_dist,
            table_count=table_count,
            average_table_size=avg_table_size,
            table_bloat_factor=bloat_factor,
            column_statistics=column_stats,
            partitioning_status=partitioning_status,
            memory_settings=memory_settings,
            checkpoint_settings=checkpoint_settings
        )
    
    def _extract_column_statistics(self, config_data: Dict) -> Dict[str, float]:
        """Extract column statistics from configuration data"""
        tables = config_data.get('tables', [])
        
        if not tables:
            return {
                'avg_columns': 10.0,
                'numeric_ratio': 0.3,
                'text_ratio': 0.4,
                'timestamp_ratio': 0.2,
                'boolean_ratio': 0.1
            }
        
        total_columns = 0
        type_counts = {'numeric': 0, 'text': 0, 'timestamp': 0, 'boolean': 0}
        
        for table in tables:
            columns = table.get('columns', [])
            total_columns += len(columns)
            
            for col in columns:
                data_type = col.get('data_type', '').lower()
                if 'int' in data_type or 'numeric' in data_type or 'decimal' in data_type:
                    type_counts['numeric'] += 1
                elif 'char' in data_type or 'text' in data_type:
                    type_counts['text'] += 1
                elif 'time' in data_type or 'date' in data_type:
                    type_counts['timestamp'] += 1
                elif 'bool' in data_type:
                    type_counts['boolean'] += 1
        
        avg_columns = total_columns / len(tables) if tables else 0
        
        return {
            'avg_columns': avg_columns,
            'numeric_ratio': type_counts['numeric'] / max(total_columns, 1),
            'text_ratio': type_counts['text'] / max(total_columns, 1),
            'timestamp_ratio': type_counts['timestamp'] / max(total_columns, 1),
            'boolean_ratio': type_counts['boolean'] / max(total_columns, 1)
        }
    
    def _extract_partitioning_status(self, config_data: Dict) -> Dict[str, float]:
        """Extract partitioning status from configuration"""
        # This would analyze partitioned tables
        # For now, return placeholder
        return {
            'partitioned_ratio': 0.1,
            'avg_partitions': 5.0,
            'partition_size_variance': 0.3
        }
    
    def _extract_performance_features(self, performance_data: Dict) -> PerformanceFeatures:
        """Extract performance features from raw data"""
        return PerformanceFeatures(
            query_latency_stats={
                'mean': performance_data.get('mean_latency', 0),
                'std': performance_data.get('std_latency', 0),
                'min': performance_data.get('min_latency', 0),
                'max': performance_data.get('max_latency', 0)
            },
            transaction_latency=performance_data.get('transaction_latency', 0),
            read_throughput=performance_data.get('read_throughput', 0),
            write_throughput=performance_data.get('write_throughput', 0),
            total_throughput=performance_data.get('total_throughput', 0),
            cpu_utilization=performance_data.get('cpu_utilization', 0),
            memory_utilization=performance_data.get('memory_utilization', 0),
            disk_io_utilization=performance_data.get('disk_io_utilization', 0),
            error_rate=performance_data.get('error_rate', 0),
            timeout_rate=performance_data.get('timeout_rate', 0),
            replication_lag=performance_data.get('replication_lag', 0)
        )
    
    def _workload_to_vector(self, features: WorkloadFeatures) -> np.ndarray:
        """Convert workload features to vector"""
        vectors = []
        
        # Query type distribution (4 dims)
        query_vec = np.array([
            features.query_type_distribution.get('select', 0),
            features.query_type_distribution.get('insert', 0),
            features.query_type_distribution.get('update', 0),
            features.query_type_distribution.get('delete', 0)
        ])
        vectors.append(query_vec)
        
        # Query complexity (5 dims)
        complexity_vec = np.array([
            features.query_complexity_features.get('avg_joins', 0),
            features.query_complexity_features.get('avg_filters', 0),
            features.query_complexity_features.get('avg_sorts', 0),
            features.query_complexity_features.get('avg_subqueries', 0),
            features.query_complexity_features.get('avg_ctes', 0)
        ])
        vectors.append(complexity_vec)
        
        # Temporal features
        if self.include_temporal:
            # Hourly pattern (24 dims)
            vectors.append(np.array(features.hourly_pattern))
            
            # Current time features (2 dims)
            time_vec = np.array([
                features.minute_of_hour,
                features.day_of_week
            ])
            vectors.append(time_vec)
        
        # Access patterns (up to 50 dims)
        access_values = list(features.table_access_frequency.values())
        if len(access_values) < 50:
            access_values.extend([0.0] * (50 - len(access_values)))
        access_vec = np.array(access_values[:50])
        vectors.append(access_vec)
        
        # Index usage (5 dims)
        index_usage = features.index_usage_pattern
        index_vec = np.array([
            index_usage.get('btree_usage', 0),
            index_usage.get('gin_usage', 0),
            index_usage.get('gist_usage', 0),
            index_usage.get('hash_usage', 0),
            index_usage.get('brin_usage', 0)
        ])
        vectors.append(index_vec)
        
        # Performance metrics (6 dims)
        perf_vec = np.array([
            features.latency_percentiles.get('p50', 0),
            features.latency_percentiles.get('p95', 0),
            features.latency_percentiles.get('p99', 0),
            features.throughput,
            features.cache_hit_ratio,
            features.connections_ratio,
            features.lock_wait_ratio
        ])
        vectors.append(perf_vec)
        
        # Concatenate all vectors
        return np.concatenate(vectors)
    
    def _configuration_to_vector(self, features: ConfigurationFeatures) -> np.ndarray:
        """Convert configuration features to vector"""
        vectors = []
        
        # Index features (4 dims)
        index_vec = np.array([
            features.index_count,
            features.index_coverage,
            features.index_size_ratio,
            features.index_usage_distribution.get('used_ratio', 0)
        ])
        vectors.append(index_vec)
        
        # Table features (3 dims)
        table_vec = np.array([
            features.table_count,
            features.average_table_size,
            features.table_bloat_factor
        ])
        vectors.append(table_vec)
        
        # Schema features (5 dims)
        schema_vec = np.array([
            features.column_statistics.get('avg_columns', 0),
            features.column_statistics.get('numeric_ratio', 0),
            features.column_statistics.get('text_ratio', 0),
            features.column_statistics.get('timestamp_ratio', 0),
            features.column_statistics.get('boolean_ratio', 0)
        ])
        vectors.append(schema_vec)
        
        # Partitioning features (3 dims)
        partition_vec = np.array([
            features.partitioning_status.get('partitioned_ratio', 0),
            features.partitioning_status.get('avg_partitions', 0),
            features.partitioning_status.get('partition_size_variance', 0)
        ])
        vectors.append(partition_vec)
        
        # Memory settings (3 dims)
        memory_vec = np.array([
            features.memory_settings.get('shared_buffers', 0),
            features.memory_settings.get('work_mem', 0),
            features.memory_settings.get('maintenance_work_mem', 0)
        ])
        vectors.append(memory_vec)
        
        # Checkpoint settings (2 dims)
        checkpoint_vec = np.array([
            features.checkpoint_settings.get('checkpoint_timeout', 0),
            features.checkpoint_settings.get('checkpoint_completion_target', 0)
        ])
        vectors.append(checkpoint_vec)
        
        return np.concatenate(vectors)
    
    def _performance_to_vector(self, features: PerformanceFeatures) -> np.ndarray:
        """Convert performance features to vector"""
        vectors = []
        
        # Latency features (4 dims)
        latency_vec = np.array([
            features.query_latency_stats.get('mean', 0),
            features.query_latency_stats.get('std', 0),
            features.query_latency_stats.get('min', 0),
            features.query_latency_stats.get('max', 0)
        ])
        vectors.append(latency_vec)
        
        # Transaction latency (1 dim)
        vectors.append(np.array([features.transaction_latency]))
        
        # Throughput features (3 dims)
        throughput_vec = np.array([
            features.read_throughput,
            features.write_throughput,
            features.total_throughput
        ])
        vectors.append(throughput_vec)
        
        # Resource utilization (3 dims)
        resource_vec = np.array([
            features.cpu_utilization,
            features.memory_utilization,
            features.disk_io_utilization
        ])
        vectors.append(resource_vec)
        
        # Quality metrics (3 dims)
        quality_vec = np.array([
            features.error_rate,
            features.timeout_rate,
            features.replication_lag
        ])
        vectors.append(quality_vec)
        
        return np.concatenate(vectors)
    
    def _adjust_dimension(self, vector: np.ndarray) -> np.ndarray:
        """Adjust vector to target dimension"""
        current_dim = len(vector)
        
        if current_dim < self.feature_dim:
            # Pad with zeros
            padding = np.zeros(self.feature_dim - current_dim)
            return np.concatenate([vector, padding])
        elif current_dim > self.feature_dim:
            # Truncate
            return vector[:self.feature_dim]
        else:
            return vector
    
    def _normalize_vector(self, vector: np.ndarray) -> np.ndarray:
        """Normalize vector using learned statistics"""
        vector_id = 'state_vector'
        
        if vector_id not in self.scalers:
            self.scalers[vector_id] = StandardScaler()
            # Fit with initial data (would need actual data in production)
            # For now, we'll use MinMaxScaler as placeholder
            self.scalers[vector_id] = MinMaxScaler()
            # Initialize with dummy data
            dummy_data = np.random.randn(100, len(vector))
            self.scalers[vector_id].fit(dummy_data)
        
        # Reshape for scaler
        vector_2d = vector.reshape(1, -1)
        normalized = self.scalers[vector_id].transform(vector_2d)
        
        return normalized.flatten()
    
    def fit_normalizer(self, training_data: List[np.ndarray]):
        """Fit normalizer with training data"""
        if not training_data:
            return
        
        # Stack all vectors
        data_matrix = np.vstack(training_data)
        
        # Fit scaler
        self.scalers['state_vector'] = StandardScaler()
        self.scalers['state_vector'].fit(data_matrix)
    
    def extract_batch_vectors(self, 
                             batch_data: List[Tuple[Dict, Dict, Dict]]) -> np.ndarray:
        """Extract state vectors for a batch of data"""
        vectors = []
        
        for workload, config, performance in batch_data:
            vector = self.extract_state_vector(workload, config, performance)
            vectors.append(vector)
        
        return np.vstack(vectors)
    
    def get_feature_names(self) -> List[str]:
        """Get names of features for interpretability"""
        names = []
        
        # Workload feature names
        names.extend(['query_select', 'query_insert', 'query_update', 'query_delete'])
        names.extend(['complexity_joins', 'complexity_filters', 'complexity_sorts', 
                     'complexity_subqueries', 'complexity_ctes'])
        
        if self.include_temporal:
            names.extend([f'hour_{i}' for i in range(24)])
            names.extend(['minute_of_hour', 'day_of_week'])
        
        names.extend([f'table_access_{i}' for i in range(50)])
        names.extend(['index_btree', 'index_gin', 'index_gist', 'index_hash', 'index_brin'])
        names.extend(['latency_p50', 'latency_p95', 'latency_p99', 'throughput', 
                     'cache_hit', 'connections_ratio', 'lock_wait_ratio'])
        
        # Configuration feature names
        names.extend(['index_count', 'index_coverage', 'index_size_ratio', 'index_used_ratio'])
        names.extend(['table_count', 'avg_table_size', 'table_bloat'])
        names.extend(['avg_columns', 'col_numeric_ratio', 'col_text_ratio', 
                     'col_timestamp_ratio', 'col_boolean_ratio'])
        names.extend(['partition_ratio', 'avg_partitions', 'partition_variance'])
        names.extend(['shared_buffers', 'work_mem', 'maintenance_work_mem'])
        names.extend(['checkpoint_timeout', 'checkpoint_target'])
        
        # Performance feature names
        names.extend(['latency_mean', 'latency_std', 'latency_min', 'latency_max'])
        names.extend(['transaction_latency'])
        names.extend(['read_throughput', 'write_throughput', 'total_throughput'])
        names.extend(['cpu_util', 'memory_util', 'disk_util'])
        names.extend(['error_rate', 'timeout_rate', 'replication_lag'])
        
        # Truncate or pad to match actual vector size
        if len(names) < self.feature_dim:
            names.extend([f'feature_{i}' for i in range(len(names), self.feature_dim)])
        else:
            names = names[:self.feature_dim]
        
        return names

# Utility functions
def create_feature_extractor(config: Dict[str, Any] = None) -> FeatureExtractor:
    """Create a feature extractor with given configuration"""
    if config is None:
        config = {
            'normalize': True,
            'include_temporal': True,
            'feature_dim': 256
        }
    
    return FeatureExtractor(**config)

def extract_features_from_snapshot(snapshot_file: str, 
                                  extractor: FeatureExtractor) -> np.ndarray:
    """Extract features from a saved snapshot file"""
    import json
    
    with open(snapshot_file, 'r') as f:
        snapshot = json.load(f)
    
    # Separate data (in real scenario, would come from different sources)
    workload_data = {
        'query_type_distribution': {'select': 0.7, 'insert': 0.2, 'update': 0.1},
        'performance_metrics': {
            'latency_percentiles': {'p50': 10, 'p95': 50, 'p99': 100},
            'throughput_avg': 1000,
            'cache_hit_ratio_avg': 0.95
        },
        'temporal_patterns': {i: {'query_count': i*10, 'total_time': i*100} for i in range(24)},
        'top_tables': [{'table': f'table_{i}', 'accesses': i*100} for i in range(50)],
        'connections_ratio': 0.5,
        'lock_wait_ratio': 0.01
    }
    
    config_data = snapshot
    performance_data = {
        'mean_latency': 25.5,
        'std_latency': 15.2,
        'min_latency': 1.0,
        'max_latency': 200.0,
        'transaction_latency': 30.0,
        'read_throughput': 800,
        'write_throughput': 200,
        'total_throughput': 1000,
        'cpu_utilization': 0.65,
        'memory_utilization': 0.75,
        'disk_io_utilization': 0.45,
        'error_rate': 0.001,
        'timeout_rate': 0.0005,
        'replication_lag': 0.0
    }
    
    return extractor.extract_state_vector(workload_data, config_data, performance_data)

if __name__ == "__main__":
    # Example usage
    extractor = create_feature_extractor()
    
    # Example data
    workload_example = {
        'query_type_distribution': {'select': 0.7, 'insert': 0.2, 'update': 0.1},
        'performance_metrics': {
            'latency_percentiles': {'p50': 10, 'p95': 50, 'p99': 100},
            'throughput_avg': 1000,
            'cache_hit_ratio_avg': 0.95
        },
        'temporal_patterns': {i: {'query_count': i*10, 'total_time': i*100} for i in range(24)},
        'top_tables': [{'table': f'table_{i}', 'accesses': i*100} for i in range(50)],
        'connections_ratio': 0.5,
        'lock_wait_ratio': 0.01
    }
    
    config_example = {
        'summary': {
            'total_indexes': 50,
            'total_tables': 10,
            'used_indexes': 40,
            'unused_indexes': 10,
            'total_index_size': 1024 * 1024 * 100,  # 100MB
            'total_database_size': 1024 * 1024 * 500,  # 500MB
            'average_table_size': 1024 * 1024 * 50,  # 50MB
            'index_efficiency': 0.85
        },
        'tables': [],
        'configuration': {
            'settings': {
                'shared_buffers': '128MB',
                'work_mem': '4MB',
                'maintenance_work_mem': '64MB',
                'checkpoint_timeout': '300',
                'checkpoint_completion_target': '0.9'
            }
        }
    }
    
    performance_example = {
        'mean_latency': 25.5,
        'std_latency': 15.2,
        'min_latency': 1.0,
        'max_latency': 200.0,
        'transaction_latency': 30.0,
        'read_throughput': 800,
        'write_throughput': 200,
        'total_throughput': 1000,
        'cpu_utilization': 0.65,
        'memory_utilization': 0.75,
        'disk_io_utilization': 0.45,
        'error_rate': 0.001,
        'timeout_rate': 0.0005,
        'replication_lag': 0.0
    }
    
    # Extract features
    state_vector = extractor.extract_state_vector(
        workload_example, 
        config_example, 
        performance_example
    )
    
    print(f"State vector shape: {state_vector.shape}")
    print(f"State vector dimension: {len(state_vector)}")
    print(f"First 10 features: {state_vector[:10]}")
    
    # Get feature names
    feature_names = extractor.get_feature_names()
    print(f"\nFirst 10 feature names: {feature_names[:10]}")
