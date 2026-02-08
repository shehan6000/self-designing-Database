# Self-Designing Database System - Complete Implementation
# This script creates all files for the 4-prompt system

# Create project structure
$projectRoot = "SelfDesigningDB"
New-Item -ItemType Directory -Force -Path $projectRoot
Set-Location $projectRoot

Write-Host "Creating Self-Designing Database System..." -ForegroundColor Green

# ============================================================================
# PROMPT 1: FOUNDATIONAL INFRASTRUCTURE & MONITORING
# ============================================================================

Write-Host "`nCreating Prompt 1: Foundational Infrastructure & Monitoring..." -ForegroundColor Cyan

# Create directory structure for Prompt 1
$dirs = @(
    "docker", "src/monitoring", "src/feature_extractor", 
    "grafana/dashboards", "grafana/provisioning/datasources",
    "grafana/provisioning/dashboards", "notebooks", "scripts",
    "config", "tests/monitoring"
)

foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Force -Path $dir
}

# 1. DOCKER COMPOSE SETUP
$dockerCompose = @'
version: '3.8'

services:
  postgres:
    image: postgres:16
    container_name: self-designing-postgres
    environment:
      POSTGRES_DB: self_designing_db
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: admin123
      POSTGRES_INITDB_ARGS: "--locale-provider=icu --icu-locale=en-US"
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./docker/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql
      - ./docker/postgres/postgresql.conf:/etc/postgresql/postgresql.conf
    command: >
      postgres -c config_file=/etc/postgresql/postgresql.conf
        -c shared_preload_libraries='pg_stat_statements,auto_explain,pg_partman_bgw'
        -c auto_explain.log_min_duration=0
        -c auto_explain.log_analyze=true
        -c pg_stat_statements.track=all
        -c pg_stat_statements.max=10000
    networks:
      - monitoring_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U admin -d self_designing_db"]
      interval: 10s
      timeout: 5s
      retries: 5

  prometheus:
    image: prom/prometheus:latest
    container_name: self-designing-prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./docker/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    networks:
      - monitoring_network
    depends_on:
      postgres-exporter:
        condition: service_healthy

  grafana:
    image: grafana/grafana:latest
    container_name: self-designing-grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/etc/grafana/dashboards
    networks:
      - monitoring_network
    depends_on:
      - prometheus

  postgres-exporter:
    image: prometheuscommunity/postgres-exporter:latest
    container_name: self-designing-postgres-exporter
    ports:
      - "9187:9187"
    environment:
      DATA_SOURCE_NAME: "postgresql://admin:admin123@postgres:5432/self_designing_db?sslmode=disable"
      PG_EXPORTER_EXTEND_QUERY_PATH: /etc/postgres-exporter/queries.yaml
    volumes:
      - ./docker/postgres-exporter/queries.yaml:/etc/postgres-exporter/queries.yaml
    networks:
      - monitoring_network
    healthcheck:
      test: ["CMD", "wget", "-q", "-O-", "http://localhost:9187/metrics"]
      interval: 30s
      timeout: 10s
      retries: 3

  jupyter:
    image: jupyter/datascience-notebook:python-3.11
    container_name: self-designing-jupyter
    ports:
      - "8888:8888"
    environment:
      - JUPYTER_ENABLE_LAB=yes
      - JUPYTER_TOKEN=designingdb
    volumes:
      - ./notebooks:/home/jovyan/work
      - ./src:/home/jovyan/src
      - ./requirements.txt:/home/jovyan/requirements.txt
    networks:
      - monitoring_network
    command: >
      start-notebook.sh
      --NotebookApp.token='designingdb'
      --NotebookApp.password=''
      --NotebookApp.notebook_dir=/home/jovyan/work
      --NotebookApp.allow_origin='*'

  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: self-designing-pgadmin
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@designingdb.com
      PGADMIN_DEFAULT_PASSWORD: admin123
    ports:
      - "5050:80"
    volumes:
      - pgadmin_data:/var/lib/pgadmin
    networks:
      - monitoring_network

volumes:
  postgres_data:
  prometheus_data:
  grafana_data:
  pgadmin_data:

networks:
  monitoring_network:
    driver: bridge
'@

$dockerCompose | Out-File -FilePath "docker-compose.yml" -Encoding UTF8

# Create PostgreSQL initialization script
$postgresInit = @'
-- Initialize the self-designing database
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS auto_explain;
CREATE EXTENSION IF NOT EXISTS pg_partman;

-- Create sample tables for testing
CREATE TABLE IF NOT EXISTS customers (
    customer_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active',
    region VARCHAR(50),
    credit_limit DECIMAL(10,2) DEFAULT 1000.00
);

CREATE TABLE IF NOT EXISTS orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(customer_id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    shipping_address TEXT,
    INDEX idx_orders_customer (customer_id),
    INDEX idx_orders_date (order_date)
);

CREATE TABLE IF NOT EXISTS products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    category VARCHAR(100),
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES products(product_id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    INDEX idx_order_items_order (order_id),
    INDEX idx_order_items_product (product_id)
);

-- Create hypertable for time-series data (if using TimescaleDB extension)
CREATE TABLE IF NOT EXISTS metrics (
    time TIMESTAMP NOT NULL,
    metric_name VARCHAR(100) NOT NULL,
    value DOUBLE PRECISION NOT NULL,
    tags JSONB
);

-- Create views for monitoring
CREATE OR REPLACE VIEW vw_query_stats AS
SELECT 
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    rows,
    shared_blks_hit,
    shared_blks_read,
    local_blks_hit,
    local_blks_read,
    temp_blks_read,
    temp_blks_written
FROM pg_stat_statements
ORDER BY total_exec_time DESC;

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO admin;
'@

New-Item -ItemType Directory -Force -Path "docker/postgres"
$postgresInit | Out-File -FilePath "docker/postgres/init.sql" -Encoding UTF8

# Create PostgreSQL configuration
$postgresConf = @'
# PostgreSQL Configuration for Self-Designing Database
listen_addresses = '*'
port = 5432
max_connections = 200
shared_buffers = 256MB
effective_cache_size = 2GB
work_mem = 16MB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
max_wal_size = 2GB
min_wal_size = 1GB

# Monitoring extensions
shared_preload_libraries = 'pg_stat_statements,auto_explain,pg_partman_bgw'
pg_stat_statements.max = 10000
pg_stat_statements.track = all
pg_stat_statements.save = on

# Auto explain for query analysis
auto_explain.log_min_duration = 0
auto_explain.log_analyze = true
auto_explain.log_buffers = true
auto_explain.log_timing = true
auto_explain.log_triggers = true
auto_explain.log_verbose = true
auto_explain.log_nested_statements = true

# Performance tuning
log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0
'@

$postgresConf | Out-File -FilePath "docker/postgres/postgresql.conf" -Encoding UTF8

# Create Prometheus configuration
New-Item -ItemType Directory -Force -Path "docker/prometheus"
$prometheusConfig = @'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

rule_files:
  - "alert_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['postgres-exporter:9187']
    scrape_interval: 10s
    scrape_timeout: 5s
    metrics_path: /metrics

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'custom-metrics'
    static_configs:
      - targets: ['jupyter:8888']
    metrics_path: /metrics
    scrape_interval: 30s

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
'@

$prometheusConfig | Out-File -FilePath "docker/prometheus/prometheus.yml" -Encoding UTF8

# Create Postgres exporter queries
New-Item -ItemType Directory -Force -Path "docker/postgres-exporter"
$exporterQueries = @'
pg_stat_statements:
  query: |
    SELECT
      queryid,
      query,
      calls,
      total_exec_time,
      mean_exec_time,
      rows,
      100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) AS hit_percent
    FROM pg_stat_statements
    WHERE query !~* '^pg_stat_statements'
  metrics:
    - queryid:
        usage: "LABEL"
        description: "Query ID"
    - query:
        usage: "LABEL"
        description: "Query text"
    - calls:
        usage: "COUNTER"
        description: "Number of times executed"
    - total_exec_time:
        usage: "GAUGE"
        description: "Total execution time in milliseconds"
    - mean_exec_time:
        usage: "GAUGE"
        description: "Mean execution time in milliseconds"
    - rows:
        usage: "COUNTER"
        description: "Total rows retrieved or affected"
    - hit_percent:
        usage: "GAUGE"
        description: "Buffer cache hit percentage"

pg_stat_user_tables:
  query: |
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
      n_dead_tup,
      last_vacuum,
      last_autovacuum,
      last_analyze,
      last_autoanalyze
    FROM pg_stat_user_tables
  metrics:
    - schemaname:
        usage: "LABEL"
        description: "Schema name"
    - relname:
        usage: "LABEL"
        description: "Relation name"
    - seq_scan:
        usage: "COUNTER"
        description: "Number of sequential scans"
    - seq_tup_read:
        usage: "COUNTER"
        description: "Number of tuples read sequentially"
    - idx_scan:
        usage: "COUNTER"
        description: "Number of index scans"
    - idx_tup_fetch:
        usage: "COUNTER"
        description: "Number of tuples fetched by index"
    - n_tup_ins:
        usage: "COUNTER"
        description: "Number of tuples inserted"
    - n_tup_upd:
        usage: "COUNTER"
        description: "Number of tuples updated"
    - n_tup_del:
        usage: "COUNTER"
        description: "Number of tuples deleted"
    - n_live_tup:
        usage: "GAUGE"
        description: "Number of live tuples"
    - n_dead_tup:
        usage: "GAUGE"
        description: "Number of dead tuples"
'@

$exporterQueries | Out-File -FilePath "docker/postgres-exporter/queries.yaml" -Encoding UTF8

# Create Grafana provisioning
$grafanaDatasource = @'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
'@

$grafanaDatasource | Out-File -FilePath "grafana/provisioning/datasources/datasource.yml" -Encoding UTF8

$grafanaDashboardProvisioning = @'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /etc/grafana/dashboards
'@

$grafanaDashboardProvisioning | Out-File -FilePath "grafana/provisioning/dashboards/dashboard.yml" -Encoding UTF8

# 2. WORKLOAD MONITORING SYSTEM
Write-Host "Creating Workload Monitoring System..." -ForegroundColor Yellow

$monitoringModule = @'
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
'@

$monitoringModule | Out-File -FilePath "src/monitoring/workload_monitor.py" -Encoding UTF8

# 3. DATABASE STATE INSPECTOR
Write-Host "Creating Database State Inspector..." -ForegroundColor Yellow

$stateInspector = @'
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
'@

$stateInspector | Out-File -FilePath "src/monitoring/db_inspector.py" -Encoding UTF8

# 4. FEATURE EXTRACTION PIPELINE
Write-Host "Creating Feature Extraction Pipeline..." -ForegroundColor Yellow

$featureExtractor = @'
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
'@

$featureExtractor | Out-File -FilePath "src/feature_extractor/pipeline.py" -Encoding UTF8

# Create requirements file
$requirements = @'
# Core dependencies
psycopg2-binary>=2.9.6
numpy>=1.24.0
pandas>=2.0.0
scikit-learn>=1.3.0
scipy>=1.10.0

# Monitoring and metrics
prometheus-client>=0.17.0
psutil>=5.9.0
pyyaml>=6.0

# Data processing and ML
torch>=2.0.0
ray[rllib]>=2.5.0
gymnasium>=0.28.0
stable-baselines3>=2.0.0

# Visualization and analysis
matplotlib>=3.7.0
seaborn>=0.12.0
plotly>=5.14.0
jupyter>=1.0.0
notebook>=6.5.0

# Utilities
tqdm>=4.65.0
python-dotenv>=1.0.0
loguru>=0.7.0
colorlog>=6.7.0

# Testing
pytest>=7.3.0
pytest-asyncio>=0.21.0
pytest-cov>=4.1.0

# Development
black>=23.3.0
flake8>=6.0.0
mypy>=1.3.0
pre-commit>=3.3.0
'@

$requirements | Out-File -FilePath "requirements.txt" -Encoding UTF8

# Create setup scripts
$setupScript = @'
#!/bin/bash
# Setup script for Self-Designing Database System

set -e

echo "Setting up Self-Designing Database System..."

# Create virtual environment
echo "Creating virtual environment..."
python3.11 -m venv venv
source venv/bin/activate

# Install dependencies
echo "Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Install the package in development mode
echo "Installing package in development mode..."
pip install -e .

# Create necessary directories
echo "Creating directories..."
mkdir -p data/snapshots
mkdir -p data/models
mkdir -p logs
mkdir -p tests/data

# Set up pre-commit hooks
echo "Setting up pre-commit hooks..."
pre-commit install

# Initialize git if not already
if [ ! -d .git ]; then
    echo "Initializing git repository..."
    git init
    git add .
    git commit -m "Initial commit: Self-Designing Database System"
fi

echo "Setup complete!"
echo ""
echo "To start the system:"
echo "1. Start Docker Compose: docker-compose up -d"
echo "2. Activate virtual environment: source venv/bin/activate"
echo "3. Run monitoring: python -m src.monitoring.workload_monitor"
echo ""
echo "Access services:"
echo "- Grafana: http://localhost:3000 (admin/admin)"
echo "- Jupyter: http://localhost:8888 (token: designingdb)"
echo "- PostgreSQL: localhost:5432"
echo "- pgAdmin: http://localhost:5050 (admin@designingdb.com/admin123)"
'@

$setupScript | Out-File -FilePath "setup.sh" -Encoding UTF8 -NoNewline

# Create Makefile
$makefile = @'
.PHONY: help start stop monitor test clean setup

help:
	@echo "Self-Designing Database System"
	@echo ""
	@echo "Commands:"
	@echo "  make start      - Start all services with Docker Compose"
	@echo "  make stop       - Stop all services"
	@echo "  make restart    - Restart all services"
	@echo "  make monitor    - Start the workload monitor"
	@echo "  make test       - Run tests"
	@echo "  make clean      - Clean up Docker resources"
	@echo "  make setup      - Set up development environment"
	@echo "  make notebook   - Start Jupyter notebook"
	@echo "  make dashboard  - Open Grafana dashboard"

start:
	docker-compose up -d
	@echo "Services started. Use 'make logs' to view logs."

stop:
	docker-compose down
	@echo "Services stopped."

restart: stop start
	@echo "Services restarted."

logs:
	docker-compose logs -f

monitor:
	source venv/bin/activate && python -m src.monitoring.workload_monitor

notebook:
	@echo "Opening Jupyter Notebook at http://localhost:8888"
	@echo "Token: designingdb"
	open http://localhost:8888 || xdg-open http://localhost:8888 || echo "Please open http://localhost:8888 in your browser"

dashboard:
	@echo "Opening Grafana at http://localhost:3000"
	@echo "Username: admin"
	@echo "Password: admin"
	open http://localhost:3000 || xdg-open http://localhost:3000 || echo "Please open http://localhost:3000 in your browser"

test:
	source venv/bin/activate && pytest tests/ -v

test-coverage:
	source venv/bin/activate && pytest tests/ -v --cov=src --cov-report=html

clean:
	docker-compose down -v
	docker system prune -f
	rm -rf data/snapshots/*.json
	rm -rf logs/*.log
	@echo "Cleaned up."

setup:
	chmod +x setup.sh
	./setup.sh

snapshot:
	source venv/bin/activate && python scripts/create_snapshot.py

analyze:
	source venv/bin/activate && python scripts/analyze_workload.py

# Database operations
db-connect:
	psql -h localhost -p 5432 -U admin -d self_designing_db

db-backup:
	docker exec self-designing-postgres pg_dump -U admin self_designing_db > backup_$(date +%Y%m%d_%H%M%S).sql

db-restore:
	@read -p "Enter backup file: " file; \
	cat $$file | docker exec -i self-designing-postgres psql -U admin self_designing_db

# Development
format:
	black src/ tests/ scripts/
	isort src/ tests/ scripts/

lint:
	flake8 src/ tests/ scripts/
	mypy src/

check: format lint test
	@echo "All checks passed!"

reset: stop clean start
	@echo "System reset complete."
'@

$makefile | Out-File -FilePath "Makefile" -Encoding UTF8 -NoNewline

# Create example notebook
Write-Host "Creating example notebooks..." -ForegroundColor Yellow

$exampleNotebook = @'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Self-Designing Database: Monitoring System Demo\n",
    "\n",
    "This notebook demonstrates the workload monitoring and feature extraction system."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Import required modules\n",
    "import sys\n",
    "import os\n",
    "sys.path.append('../src')\n",
    "\n",
    "from monitoring.workload_monitor import WorkloadMonitor\n",
    "from monitoring.db_inspector import DatabaseInspector\n",
    "from feature_extractor.pipeline import FeatureExtractor\n",
    "\n",
    "import pandas as pd\n",
    "import numpy as np\n",
    "import matplotlib.pyplot as plt\n",
    "import seaborn as sns\n",
    "\n",
    "# Set plot style\n",
    "plt.style.use('seaborn-v0_8-darkgrid')\n",
    "sns.set_palette('husl')"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "## 1. Initialize Database Inspector"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Database connection parameters\n",
    "db_config = {\n",
    "    'host': 'localhost',\n",
    "    'port': 5432,\n",
    "    'database': 'self_designing_db',\n",
    "    'user': 'admin',\n",
    "    'password': 'admin123'\n",
    "}\n",
    "\n",
    "# Create inspector\n",
    "inspector = DatabaseInspector(db_config)\n",
    "inspector.connect()\n",
    "\n",
    "print(\"Database Inspector initialized\")"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "## 2. Create Database Snapshot"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Create a snapshot\n",
    "snapshot = inspector.create_snapshot(\"initial_snapshot\")\n",
    "\n",
    "# Display summary\n",
    "summary = snapshot['summary']\n",
    "print(\"Database Snapshot Summary:\")\n",
    "print(f\"Total Tables: {summary['total_tables']}\")\n",
    "print(f\"Total Indexes: {summary['total_indexes']}\")\n",
    "print(f\"Used Indexes: {summary['used_indexes']}\")\n",
    "print(f\"Unused Indexes: {summary['unused_indexes']}\")\n",
    "print(f\"Total Database Size: {summary['total_database_size'] / (1024**3):.2f} GB\")"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "## 3. Analyze Index Usage"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Get all indexes\n",
    "indexes = inspector.get_all_indexes()\n",
    "\n",
    "# Create DataFrame for analysis\n",
    "index_data = []\n",
    "for idx in indexes:\n",
    "    index_data.append({\n",
    "        'name': idx.index_name,\n",
    "        'table': idx.table_name,\n",
    "        'type': idx.index_type,\n",
    "        'size_mb': idx.index_size_bytes / (1024**2),\n",
    "        'scans': idx.index_scan_count,\n",
    "        'fetches': idx.index_tup_fetch,\n",
    "        'usage_ratio': idx.usage_ratio,\n",
    "        'efficiency': idx.efficiency\n",
    "    })\n",
    "\n",
    "df_indexes = pd.DataFrame(index_data)\n",
    "\n",
    "# Display top 10 indexes by size\n",
    "print(\"Top 10 Indexes by Size:\")\n",
    "print(df_indexes.nlargest(10, 'size_mb')[['name', 'table', 'size_mb', 'scans', 'usage_ratio']])"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Visualize index usage\n",
    "fig, axes = plt.subplots(2, 2, figsize=(15, 10))\n",
    "\n",
    "# 1. Index size distribution\n",
    "axes[0, 0].hist(df_indexes['size_mb'], bins=20, edgecolor='black')\n",
    "axes[0, 0].set_xlabel('Index Size (MB)')\n",
    "axes[0, 0].set_ylabel('Count')\n",
    "axes[0, 0].set_title('Index Size Distribution')\n",
    "\n",
    "# 2. Index usage vs size\n",
    "axes[0, 1].scatter(df_indexes['size_mb'], df_indexes['scans'], alpha=0.6)\n",
    "axes[0, 1].set_xlabel('Index Size (MB)')\n",
    "axes[0, 1].set_ylabel('Number of Scans')\n",
    "axes[0, 1].set_title('Index Usage vs Size')\n",
    "\n",
    "# 3. Index type distribution\n",
    "type_counts = df_indexes['type'].value_counts()\n",
    "axes[1, 0].pie(type_counts.values, labels=type_counts.index, autopct='%1.1f%%')\n",
    "axes[1, 0].set_title('Index Type Distribution')\n",
    "\n",
    "# 4. Usage ratio distribution\n",
    "axes[1, 1].hist(df_indexes['usage_ratio'].fillna(0), bins=20, edgecolor='black')\n",
    "axes[1, 1].set_xlabel('Usage Ratio')\n",
    "axes[1, 1].set_ylabel('Count')\n",
    "axes[1, 1].set_title('Index Usage Ratio Distribution')\n",
    "\n",
    "plt.tight_layout()\n",
    "plt.show()"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "## 4. Initialize Workload Monitor"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Initialize workload monitor\n",
    "monitor = WorkloadMonitor(db_config, poll_interval=10)\n",
    "\n",
    "# Simulate monitoring for a short period\n",
    "import asyncio\n",
    "\n",
    "async def demo_monitoring():\n",
    "    await monitor.connect()\n",
    "    \n",
    "    # Collect some metrics\n",
    "    for _ in range(3):\n",
    "        query_stats = await monitor.fetch_query_statistics()\n",
    "        monitor.update_query_metrics(query_stats)\n",
    "        await asyncio.sleep(5)\n",
    "    \n",
    "    return monitor.get_workload_summary()\n",
    "\n",
    "# Run monitoring demo\n",
    "summary = await demo_monitoring()\n",
    "\n",
    "print(\"Workload Summary:\")\n",
    "print(f\"Total Queries: {summary['total_queries']}\")\n",
    "print(f\"Query Type Distribution: {summary['query_type_distribution']}\")\n",
    "print(f\"Average Query Time: {summary['average_query_time']:.2f} ms\")\n",
    "print(f\"P95 Latency: {summary['performance_metrics']['latency_percentiles']['p95']:.2f} ms\")"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "## 5. Feature Extraction Pipeline"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Initialize feature extractor\n",
    "extractor = FeatureExtractor(normalize=True, feature_dim=256)\n",
    "\n",
    "# Create example data\n",
    "workload_example = {\n",
    "    'query_type_distribution': {'select': 0.7, 'insert': 0.2, 'update': 0.1},\n",
    "    'performance_metrics': {\n",
    "        'latency_percentiles': {'p50': 10, 'p95': 50, 'p99': 100},\n",
    "        'throughput_avg': 1000,\n",
    "        'cache_hit_ratio_avg': 0.95\n",
    "    },\n",
    "    'temporal_patterns': {i: {'query_count': i*10, 'total_time': i*100} for i in range(24)},\n",
    "    'top_tables': [{'table': f'table_{i}', 'accesses': i*100} for i in range(50)],\n",
    "    'connections_ratio': 0.5,\n",
    "    'lock_wait_ratio': 0.01\n",
    "}\n",
    "\n",
    "config_example = snapshot\n",
    "\n",
    "performance_example = {\n",
    "    'mean_latency': 25.5,\n",
    "    'std_latency': 15.2,\n",
    "    'min_latency': 1.0,\n",
    "    'max_latency': 200.0,\n",
    "    'transaction_latency': 30.0,\n",
    "    'read_throughput': 800,\n",
    "    'write_throughput': 200,\n",
    "    'total_throughput': 1000,\n",
    "    'cpu_utilization': 0.65,\n",
    "    'memory_utilization': 0.75,\n",
    "    'disk_io_utilization': 0.45,\n",
    "    'error_rate': 0.001,\n",
    "    'timeout_rate': 0.0005,\n",
    "    'replication_lag': 0.0\n",
    "}\n",
    "\n",
    "# Extract features\n",
    "state_vector = extractor.extract_state_vector(\n",
    "    workload_example,\n",
    "    config_example,\n",
    "    performance_example\n",
    ")\n",
    "\n",
    "print(f\"State vector shape: {state_vector.shape}\")\n",
    "print(f\"State vector dimension: {len(state_vector)}\")\n",
    "print(f\"\\nFirst 20 features:\")\n",
    "print(state_vector[:20])"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Visualize feature distribution\n",
    "fig, axes = plt.subplots(1, 3, figsize=(15, 5))\n",
    "\n",
    "# 1. Feature value distribution\n",
    "axes[0].hist(state_vector, bins=30, edgecolor='black')\n",
    "axes[0].set_xlabel('Feature Value')\n",
    "axes[0].set_ylabel('Frequency')\n",
    "axes[0].set_title('Feature Value Distribution')\n",
    "\n",
    "# 2. Cumulative distribution\n",
    "sorted_features = np.sort(state_vector)\n",
    "cumulative = np.arange(1, len(sorted_features) + 1) / len(sorted_features)\n",
    "axes[1].plot(sorted_features, cumulative, linewidth=2)\n",
    "axes[1].set_xlabel('Feature Value')\n",
    "axes[1].set_ylabel('Cumulative Probability')\n",
    "axes[1].set_title('Cumulative Distribution')\n",
    "axes[1].grid(True, alpha=0.3)\n",
    "\n",
    "# 3. Feature importance (placeholder - would use actual model)\n",
    "feature_importance = np.abs(state_vector)\n",
    "top_indices = np.argsort(feature_importance)[-20:]\n",
    "feature_names = extractor.get_feature_names()\n",
    "\n",
    "axes[2].barh(range(20), feature_importance[top_indices])\n",
    "axes[2].set_yticks(range(20))\n",
    "axes[2].set_yticklabels([feature_names[i] for i in top_indices], fontsize=8)\n",
    "axes[2].set_xlabel('Importance (abs value)')\n",
    "axes[2].set_title('Top 20 Features by Importance')\n",
    "\n",
    "plt.tight_layout()\n",
    "plt.show()"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "## 6. Export Metrics for Prometheus"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Export metrics in Prometheus format\n",
    "prometheus_metrics = monitor.export_metrics(format='prometheus')\n",
    "\n",
    "print(\"Prometheus Metrics (first 20 lines):\\n\")\n",
    "lines = prometheus_metrics.split('\\n')[:20]\n",
    "for line in lines:\n",
    "    print(line)"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "## 7. Clean Up"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Disconnect from database\n",
    "inspector.disconnect()\n",
    "\n",
    "print(\"Clean up complete. All connections closed.\")"
   ]
  },
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "## Summary\n",
    "\n",
    "This demo showed:\n",
    "1. Database inspection and snapshot creation\n",
    "2. Index usage analysis and visualization\n",
    "3. Workload monitoring setup\n",
    "4. Feature extraction pipeline\n",
    "5. Metrics export for monitoring\n",
    "\n",
    "The system is now ready for integration with the RL environment."
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3.11",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "name": "python",
   "version": "3.11.0"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
'@

$exampleNotebook | Out-File -FilePath "notebooks/demo_monitoring.ipynb" -Encoding UTF8

# Create Docker health check script
$healthCheck = @'
#!/bin/bash
# Health check script for Self-Designing Database System

set -e

echo "Performing health checks..."

# Check Docker services
echo "1. Checking Docker services..."
if docker-compose ps | grep -q "Up"; then
    echo "✓ All Docker services are running"
else
    echo "✗ Some Docker services are not running"
    docker-compose ps
    exit 1
fi

# Check PostgreSQL
echo "2. Checking PostgreSQL..."
if docker exec self-designing-postgres pg_isready -U admin -d self_designing_db; then
    echo "✓ PostgreSQL is ready"
else
    echo "✗ PostgreSQL is not ready"
    exit 1
fi

# Check Prometheus
echo "3. Checking Prometheus..."
if curl -s http://localhost:9090/-/healthy > /dev/null; then
    echo "✓ Prometheus is healthy"
else
    echo "✗ Prometheus is not responding"
    exit 1
fi

# Check Grafana
echo "4. Checking Grafana..."
if curl -s http://localhost:3000/api/health > /dev/null; then
    echo "✓ Grafana is healthy"
else
    echo "✗ Grafana is not responding"
    exit 1
fi

# Check Postgres Exporter
echo "5. Checking Postgres Exporter..."
if curl -s http://localhost:9187/metrics > /dev/null; then
    echo "✓ Postgres Exporter is healthy"
else
    echo "✗ Postgres Exporter is not responding"
    exit 1
fi

echo ""
echo "All health checks passed! ✅"
echo ""
echo "Services:"
echo "- Grafana:      http://localhost:3000"
echo "- Prometheus:   http://localhost:9090"
echo "- Jupyter:      http://localhost:8888"
echo "- PostgreSQL:   localhost:5432"
echo "- pgAdmin:      http://localhost:5050"
echo ""
echo "Default credentials:"
echo "- Grafana/PGAdmin: admin/admin123"
echo "- Jupyter token:   designingdb"
echo "- PostgreSQL:      admin/admin123"
'@

$healthCheck | Out-File -FilePath "scripts/health_check.sh" -Encoding UTF8 -NoNewline

# Create Grafana dashboard JSON
$grafanaDashboard = @'
{
  "dashboard": {
    "id": null,
    "uid": "self-designing-db",
    "title": "Self-Designing Database Dashboard",
    "tags": ["postgresql", "monitoring", "performance"],
    "timezone": "browser",
    "schemaVersion": 37,
    "version": 1,
    "refresh": "30s",
    "panels": [
      {
        "id": 1,
        "title": "Database Connections",
        "type": "stat",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "pg_stat_database_numbackends{datname=\"self_designing_db\"}",
            "legendFormat": "Connections"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "mappings": [],
            "thresholds": {
              "steps": [
                {
                  "color": "green",
                  "value": null
                },
                {
                  "color": "red",
                  "value": 80
                }
              ]
            },
            "unit": "short"
          }
        },
        "gridPos": {
          "h": 8,
          "w": 8,
          "x": 0,
          "y": 0
        }
      },
      {
        "id": 2,
        "title": "Query Execution Time",
        "type": "timeseries",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "rate(pg_stat_statements_total_time_seconds[5m])",
            "legendFormat": "{{queryid}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "s"
          }
        },
        "gridPos": {
          "h": 8,
          "w": 16,
          "x": 8,
          "y": 0
        }
      },
      {
        "id": 3,
        "title": "Cache Hit Ratio",
        "type": "gauge",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read)",
            "legendFormat": "Cache Hit Ratio"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "max": 1,
            "min": 0,
            "thresholds": {
              "steps": [
                {
                  "color": "red",
                  "value": null
                },
                {
                  "color": "yellow",
                  "value": 0.9
                },
                {
                  "color": "green",
                  "value": 0.95
                }
              ]
            },
            "unit": "percentunit"
          }
        },
        "gridPos": {
          "h": 8,
          "w": 8,
          "x": 0,
          "y": 8
        }
      },
      {
        "id": 4,
        "title": "Index Usage",
        "type": "timeseries",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "pg_stat_user_indexes_idx_scan",
            "legendFormat": "{{indexrelname}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short"
          }
        },
        "gridPos": {
          "h": 8,
          "w": 16,
          "x": 8,
          "y": 8
        }
      },
      {
        "id": 5,
        "title": "Query Type Distribution",
        "type": "piechart",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(pg_stat_statements_calls_total[5m])) by (query_type)",
            "legendFormat": "{{query_type}}"
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 16
        }
      },
      {
        "id": 6,
        "title": "Table Access Patterns",
        "type": "barchart",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "rate(pg_stat_user_tables_seq_scan[5m]) + rate(pg_stat_user_tables_idx_scan[5m])",
            "legendFormat": "{{relname}}"
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 16
        }
      },
      {
        "id": 7,
        "title": "Transaction Rate",
        "type": "stat",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m])",
            "legendFormat": "Transactions/sec"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "ops"
          }
        },
        "gridPos": {
          "h": 8,
          "w": 8,
          "x": 0,
          "y": 24
        }
      },
      {
        "id": 8,
        "title": "Dead Tuples",
        "type": "timeseries",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "pg_stat_user_tables_n_dead_tup",
            "legendFormat": "{{relname}}"
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 16,
          "x": 8,
          "y": 24
        }
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    }
  },
  "folderId": 0,
  "overwrite": true
}
'@

$grafanaDashboard | Out-File -FilePath "grafana/dashboards/dashboard.json" -Encoding UTF8

