#!/usr/bin/env python3
"""
Self-Designing Database System - Interactive Notebook-style Demo
Run like: python demo_notebook.py
"""

import sys
import os
import json
import time
from datetime import datetime

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def print_header(title):
    """Print a formatted header"""
    print("\n" + "=" * 70)
    print(f" {title}")
    print("=" * 70)

def print_step(step_num, title):
    """Print a step header"""
    print(f"\n▶ STEP {step_num}: {title}")
    print("-" * 50)

def print_success(message):
    """Print success message"""
    print(f"✓ {message}")

def print_error(message):
    """Print error message"""
    print(f"✗ {message}")

def print_info(message):
    """Print info message"""
    print(f"ℹ {message}")

def wait_for_user(prompt="Press Enter to continue..."):
    """Wait for user input"""
    input(f"\n{prompt}")

# ============================================================================
# CELL 1: SETUP AND IMPORTS
# ============================================================================

print_header("SELF-DESIGNING DATABASE SYSTEM - INTERACTIVE DEMO")
print("\nWelcome! This is an interactive notebook-style demo.")
print("It will guide you through the system step by step.")

wait_for_user("Ready to begin? Press Enter...")

print_step(1, "Setting up environment and installing packages")

# Check Python version
print("\nChecking Python version...")
print(f"Python {sys.version}")

# Add src to path
src_path = os.path.join(os.path.dirname(__file__), 'src')
if os.path.exists(src_path):
    sys.path.insert(0, src_path)
    print_success(f"Added 'src' directory to Python path: {src_path}")
else:
    print_error(f"'src' directory not found at: {src_path}")
    print_info("Creating src directory structure...")
    os.makedirs(src_path, exist_ok=True)
    os.makedirs(os.path.join(src_path, 'monitoring'), exist_ok=True)
    os.makedirs(os.path.join(src_path, 'feature_extractor'), exist_ok=True)

# Install required packages
print("\nChecking and installing required packages...")
required_packages = [
    'psycopg2-binary',
    'pandas',
    'numpy',
    'matplotlib',
    'seaborn',
    'scikit-learn',
    'prometheus-client',
    'psutil'
]

import subprocess
import importlib

for package in required_packages:
    package_name = package.split('-')[0].split('[')[0]
    try:
        importlib.import_module(package_name)
        print_success(f"{package} already installed")
    except ImportError:
        print(f"Installing {package}...")
        try:
            subprocess.check_call([sys.executable, '-m', 'pip', 'install', package, '-q'])
            print_success(f"Installed {package}")
        except subprocess.CalledProcessError as e:
            print_error(f"Failed to install {package}: {e}")

print_success("Package setup complete!")
wait_for_user()

# ============================================================================
# CELL 2: IMPORT LIBRARIES
# ============================================================================

print_step(2, "Importing libraries")

print("\nImporting core libraries...")
try:
    import pandas as pd
    import numpy as np
    import matplotlib.pyplot as plt
    import seaborn as sns
    import psycopg2
    from psycopg2.extras import RealDictCursor
    import psutil
    from prometheus_client import start_http_server, Gauge, Counter
    
    print_success("All core libraries imported successfully")
    
    # Set matplotlib to use Agg backend for saving files
    plt.switch_backend('Agg')
    
    # Set plotting style
    plt.style.use('seaborn-v0_8-darkgrid')
    sns.set_palette('husl')
    
except ImportError as e:
    print_error(f"Failed to import libraries: {e}")
    sys.exit(1)

print_success("Library imports complete!")
wait_for_user()

# ============================================================================
# CELL 3: TEST DATABASE CONNECTION
# ============================================================================

print_step(3, "Testing Database Connection")

# Database configuration
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'self_designing_db',
    'user': 'admin',
    'password': 'admin123'
}

print("\nTesting connection to PostgreSQL...")
try:
    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    # Get PostgreSQL version
    cursor.execute("SELECT version();")
    version = cursor.fetchone()['version']
    print_success(f"PostgreSQL Version: {version.split(',')[0]}")
    
    # Check if our database exists
    cursor.execute("SELECT datname FROM pg_database WHERE datname = 'self_designing_db';")
    if cursor.fetchone():
        print_success("Database 'self_designing_db' exists")
    else:
        print_error("Database 'self_designing_db' not found")
    
    # List tables
    cursor.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public'
        ORDER BY table_name;
    """)
    tables = cursor.fetchall()
    
    if tables:
        print_success(f"Found {len(tables)} tables:")
        for table in tables[:10]:  # Show first 10
            print(f"  - {table['table_name']}")
        if len(tables) > 10:
            print(f"  ... and {len(tables) - 10} more")
    else:
        print_info("No tables found in the database")
        print_info("This is normal for a fresh installation")
    
    # Check for monitoring extensions
    cursor.execute("""
        SELECT extname, extversion 
        FROM pg_extension 
        WHERE extname IN ('pg_stat_statements', 'auto_explain');
    """)
    extensions = cursor.fetchall()
    
    if extensions:
        print_success("Monitoring extensions found:")
        for ext in extensions:
            print(f"  - {ext['extname']} v{ext['extversion']}")
    else:
        print_info("Monitoring extensions not found")
        print_info("They will be loaded when needed")
    
    cursor.close()
    conn.close()
    print_success("Database connection test PASSED!")
    
except psycopg2.OperationalError as e:
    print_error(f"Could not connect to database: {e}")
    print("\nTroubleshooting tips:")
    print("1. Check if Docker is running: docker-compose ps")
    print("2. Check PostgreSQL logs: docker-compose logs postgres")
    print("3. Make sure services are up: docker-compose up -d")
    print("4. Wait a moment for services to start")
    wait_for_user("Press Enter to try alternative connection...")
    
    # Try alternative connection
    try:
        print("\nTrying alternative connection to 'postgres' host (Docker internal)...")
        alt_config = DB_CONFIG.copy()
        alt_config['host'] = 'postgres'  # Docker service name
        conn = psycopg2.connect(**alt_config)
        print_success("Connected using Docker internal network!")
        conn.close()
    except Exception as e2:
        print_error(f"Alternative connection also failed: {e2}")

except Exception as e:
    print_error(f"Unexpected error: {e}")

wait_for_user()

# ============================================================================
# CELL 4: GENERATE SAMPLE DATA
# ============================================================================

print_step(4, "Generating Sample Data")

print("\nCreating sample data for demonstration...")

# Create sample workload data
np.random.seed(42)  # For reproducibility

# Sample query performance data
query_types = ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'JOIN', 'AGGREGATE', 'CTE', 'WINDOW']
n_queries = len(query_types)

query_data = {
    'query_type': query_types,
    'count': np.random.randint(100, 5000, n_queries),
    'avg_time_ms': np.random.exponential(50, n_queries),
    'cache_hit_ratio': np.random.uniform(0.7, 0.98, n_queries),
    'rows_affected': np.random.randint(10, 10000, n_queries)
}

query_df = pd.DataFrame(query_data)
print_success(f"Created query performance data: {len(query_df)} query types")

# Sample table access patterns
tables = ['customers', 'orders', 'products', 'order_items', 'logs', 'metrics', 'audit', 'config']
n_tables = len(tables)

table_data = {
    'table_name': tables,
    'size_mb': np.random.exponential(100, n_tables),
    'row_count': np.random.randint(1000, 1000000, n_tables),
    'read_count': np.random.randint(1000, 100000, n_tables),
    'write_count': np.random.randint(100, 10000, n_tables),
    'index_count': np.random.randint(1, 10, n_tables)
}

table_df = pd.DataFrame(table_data)
table_df['total_access'] = table_df['read_count'] + table_df['write_count']
table_df['access_per_row'] = table_df['total_access'] / table_df['row_count']
print_success(f"Created table statistics data: {len(table_df)} tables")

# Sample time series data (hourly patterns)
hours = list(range(24))
hourly_data = {
    'hour': hours,
    'query_count': [int(1000 + 500 * np.sin(h/24 * 2*np.pi) + np.random.normal(0, 100)) for h in hours],
    'avg_latency': [50 + 20 * np.sin(h/24 * 2*np.pi) + np.random.normal(0, 5) for h in hours],
    'active_connections': [int(20 + 10 * np.sin(h/24 * 2*np.pi) + np.random.normal(0, 3)) for h in hours]
}

hourly_df = pd.DataFrame(hourly_data)
print_success(f"Created hourly pattern data: {len(hourly_df)} hours")

print("\nSample Data Preview:")
print("\n1. Query Performance (first 5 rows):")
print(query_df.head().to_string())
print("\n2. Table Statistics (first 5 rows):")
print(table_df.head().to_string())
print("\n3. Hourly Patterns (first 5 rows):")
print(hourly_df.head().to_string())

wait_for_user()

# ============================================================================
# CELL 5: DATA VISUALIZATION
# ============================================================================

print_step(5, "Creating Data Visualizations")

print("\nGenerating visualizations...")

try:
    # Create figure with subplots
    fig = plt.figure(figsize=(16, 12))
    
    # 1. Query count by type
    ax1 = plt.subplot(3, 3, 1)
    bars = ax1.bar(query_df['query_type'], query_df['count'], color='skyblue', edgecolor='black')
    ax1.set_title('Query Count by Type', fontsize=12, fontweight='bold')
    ax1.set_xlabel('Query Type')
    ax1.set_ylabel('Count')
    ax1.tick_params(axis='x', rotation=45)
    # Add value labels on bars
    for bar in bars:
        height = bar.get_height()
        ax1.text(bar.get_x() + bar.get_width()/2., height + 50,
                f'{int(height):,}', ha='center', va='bottom', fontsize=8)
    
    # 2. Average query time
    ax2 = plt.subplot(3, 3, 2)
    bars = ax2.bar(query_df['query_type'], query_df['avg_time_ms'], color='lightcoral', edgecolor='black')
    ax2.set_title('Average Query Time (ms)', fontsize=12, fontweight='bold')
    ax2.set_xlabel('Query Type')
    ax2.set_ylabel('Time (ms)')
    ax2.tick_params(axis='x', rotation=45)
    for bar in bars:
        height = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2., height + 1,
                f'{height:.1f}', ha='center', va='bottom', fontsize=8)
    
    # 3. Cache hit ratio
    ax3 = plt.subplot(3, 3, 3)
    bars = ax3.bar(query_df['query_type'], query_df['cache_hit_ratio'], color='lightgreen', edgecolor='black')
    ax3.set_title('Cache Hit Ratio', fontsize=12, fontweight='bold')
    ax3.set_xlabel('Query Type')
    ax3.set_ylabel('Hit Ratio')
    ax3.tick_params(axis='x', rotation=45)
    ax3.set_ylim(0, 1)
    for bar in bars:
        height = bar.get_height()
        ax3.text(bar.get_x() + bar.get_width()/2., height + 0.01,
                f'{height:.2f}', ha='center', va='bottom', fontsize=8)
    
    # 4. Table sizes
    ax4 = plt.subplot(3, 3, 4)
    table_df_sorted = table_df.sort_values('size_mb', ascending=False)
    bars = ax4.barh(table_df_sorted['table_name'], table_df_sorted['size_mb'], 
                   color='gold', edgecolor='black')
    ax4.set_title('Table Sizes (MB)', fontsize=12, fontweight='bold')
    ax4.set_xlabel('Size (MB)')
    for i, (bar, size) in enumerate(zip(bars, table_df_sorted['size_mb'])):
        ax4.text(size + 5, bar.get_y() + bar.get_height()/2,
                f'{size:.1f}', ha='left', va='center', fontsize=8)
    
    # 5. Read vs Write operations
    ax5 = plt.subplot(3, 3, 5)
    x = np.arange(len(tables))
    width = 0.35
    ax5.bar(x - width/2, table_df['read_count'], width, label='Reads', 
           color='cornflowerblue', edgecolor='black')
    ax5.bar(x + width/2, table_df['write_count'], width, label='Writes', 
           color='salmon', edgecolor='black')
    ax5.set_title('Read vs Write Operations', fontsize=12, fontweight='bold')
    ax5.set_xlabel('Table')
    ax5.set_ylabel('Count')
    ax5.set_xticks(x)
    ax5.set_xticklabels(tables, rotation=45, ha='right', fontsize=8)
    ax5.legend()
    
    # 6. Index count per table
    ax6 = plt.subplot(3, 3, 6)
    bars = ax6.bar(table_df['table_name'], table_df['index_count'], 
                  color='violet', edgecolor='black')
    ax6.set_title('Index Count per Table', fontsize=12, fontweight='bold')
    ax6.set_xlabel('Table')
    ax6.set_ylabel('Index Count')
    ax6.tick_params(axis='x', rotation=45)
    for bar in bars:
        height = bar.get_height()
        ax6.text(bar.get_x() + bar.get_width()/2., height + 0.1,
                f'{int(height)}', ha='center', va='bottom', fontsize=8)
    
    # 7. Hourly query count
    ax7 = plt.subplot(3, 3, 7)
    ax7.plot(hourly_df['hour'], hourly_df['query_count'], 'b-', linewidth=2, marker='o')
    ax7.fill_between(hourly_df['hour'], hourly_df['query_count'], alpha=0.3, color='blue')
    ax7.set_title('Hourly Query Pattern', fontsize=12, fontweight='bold')
    ax7.set_xlabel('Hour of Day')
    ax7.set_ylabel('Query Count')
    ax7.grid(True, alpha=0.3)
    ax7.set_xticks(range(0, 24, 3))
    
    # 8. Hourly latency
    ax8 = plt.subplot(3, 3, 8)
    ax8.plot(hourly_df['hour'], hourly_df['avg_latency'], 'r-', linewidth=2, marker='s')
    ax8.fill_between(hourly_df['hour'], hourly_df['avg_latency'], alpha=0.3, color='red')
    ax8.set_title('Hourly Average Latency', fontsize=12, fontweight='bold')
    ax8.set_xlabel('Hour of Day')
    ax8.set_ylabel('Latency (ms)')
    ax8.grid(True, alpha=0.3)
    ax8.set_xticks(range(0, 24, 3))
    
    # 9. Query count vs latency scatter
    ax9 = plt.subplot(3, 3, 9)
    scatter = ax9.scatter(query_df['count'], query_df['avg_time_ms'], 
                         s=query_df['rows_affected']/100,  # Size based on rows
                         c=query_df['cache_hit_ratio'],    # Color based on cache hit
                         cmap='viridis', alpha=0.7, edgecolor='black')
    ax9.set_title('Query Count vs Latency', fontsize=12, fontweight='bold')
    ax9.set_xlabel('Query Count')
    ax9.set_ylabel('Avg Time (ms)')
    
    # Add colorbar
    plt.colorbar(scatter, ax=ax9, label='Cache Hit Ratio')
    
    # Add text labels for query types
    for i, txt in enumerate(query_df['query_type']):
        ax9.annotate(txt, (query_df['count'][i], query_df['avg_time_ms'][i]),
                    fontsize=7, ha='center', va='bottom')
    
    plt.suptitle('Self-Designing Database System - Performance Dashboard', 
                fontsize=16, fontweight='bold', y=1.02)
    plt.tight_layout()
    
    # Save the figure
    plt.savefig('performance_dashboard.png', dpi=150, bbox_inches='tight')
    print_success("Created performance dashboard visualization")
    print_info("Saved as: performance_dashboard.png")
    
    # Show plot if in interactive environment
    try:
        plt.show()
    except:
        print_info("Plot displayed (or saved to file)")
    
    # Create a simpler summary plot
    fig2, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
    
    # Summary 1: Top 5 tables by size
    top_tables = table_df.nlargest(5, 'size_mb')
    ax1.pie(top_tables['size_mb'], labels=top_tables['table_name'], 
           autopct='%1.1f%%', startangle=90, colors=sns.color_palette('Set2'))
    ax1.set_title('Top 5 Tables by Size', fontsize=14, fontweight='bold')
    
    # Summary 2: Query type distribution
    query_totals = query_df.set_index('query_type')['count']
    ax2.pie(query_totals, labels=query_totals.index, 
           autopct='%1.1f%%', startangle=90, colors=sns.color_palette('Set3'))
    ax2.set_title('Query Type Distribution', fontsize=14, fontweight='bold')
    
    plt.tight_layout()
    plt.savefig('summary_charts.png', dpi=150, bbox_inches='tight')
    print_success("Created summary charts")
    print_info("Saved as: summary_charts.png")
    
except Exception as e:
    print_error(f"Visualization error: {e}")

wait_for_user()

# ============================================================================
# CELL 6: TEST MONITORING MODULES
# ============================================================================

print_step(6, "Testing Monitoring Modules")

print("\nTesting if monitoring modules can be imported...")

try:
    # Try to import monitoring modules
    from monitoring.workload_monitor import WorkloadMonitor
    from monitoring.db_inspector import DatabaseInspector
    from feature_extractor.pipeline import FeatureExtractor
    
    print_success("All monitoring modules imported successfully!")
    
    # Create a simple database inspector
    print("\nCreating database inspector...")
    inspector = DatabaseInspector(DB_CONFIG)
    
    try:
        inspector.connect()
        print_success("Database inspector connected")
        
        # Try to get table statistics
        tables = inspector.get_table_statistics()
        print_success(f"Retrieved statistics for {len(tables)} tables")
        
        # Try to get indexes
        indexes = inspector.get_all_indexes()
        print_success(f"Found {len(indexes)} indexes")
        
        inspector.disconnect()
        print_success("Database inspector test completed")
        
    except Exception as e:
        print_error(f"Database inspector error: {e}")
        print_info("This might be because the database is empty or tables don't exist yet")
    
    # Test feature extractor
    print("\nTesting feature extractor...")
    extractor = FeatureExtractor(normalize=True, feature_dim=128)
    print_success("Feature extractor created successfully")
    
    # Create sample data for feature extraction
    sample_workload = {
        'query_type_distribution': {'select': 0.7, 'insert': 0.2, 'update': 0.1},
        'performance_metrics': {
            'latency_percentiles': {'p50': 10, 'p95': 50, 'p99': 100},
            'throughput_avg': 1000,
            'cache_hit_ratio_avg': 0.95
        }
    }
    
    sample_config = {
        'summary': {
            'total_indexes': 50,
            'total_tables': 10,
            'used_indexes': 40,
            'unused_indexes': 10
        }
    }
    
    sample_performance = {
        'mean_latency': 25.5,
        'total_throughput': 1000,
        'cpu_utilization': 0.65
    }
    
    try:
        features = extractor.extract_state_vector(
            sample_workload, sample_config, sample_performance
        )
        print_success(f"Feature extraction successful!")
        print_info(f"Feature vector dimension: {len(features)}")
        print_info(f"Feature range: [{features.min():.4f}, {features.max():.4f}]")
    except Exception as e:
        print_error(f"Feature extraction error: {e}")
    
except ImportError as e:
    print_error(f"Could not import monitoring modules: {e}")
    print("\nThis might be because:")
    print("1. The 'src' directory structure is incomplete")
    print("2. Required modules are missing")
    print("3. There's a syntax error in the module files")
    
    # Check src directory
    print("\nChecking 'src' directory structure...")
    if os.path.exists('src'):
        print("Contents of 'src' directory:")
        for root, dirs, files in os.walk('src'):
            level = root.replace('src', '').count(os.sep)
            indent = ' ' * 2 * level
            print(f'{indent}{os.path.basename(root)}/')
            subindent = ' ' * 2 * (level + 1)
            for file in files:
                if file.endswith('.py'):
                    print(f'{subindent}{file}')
    else:
        print_error("'src' directory not found")

wait_for_user()

# ============================================================================
# CELL 7: SYSTEM HEALTH CHECK
# ============================================================================

print_step(7, "System Health Check")

print("\nChecking Docker services...")
try:
    import subprocess
    
    # Check docker-compose
    result = subprocess.run(['docker-compose', 'ps'], 
                          capture_output=True, text=True, shell=True)
    
    if result.returncode == 0:
        print_success("Docker Compose is working")
        lines = result.stdout.strip().split('\n')
        
        if len(lines) > 2:  # Has services
            print("\nRunning services:")
            for line in lines[2:]:  # Skip header
                if line.strip():
                    parts = line.split()
                    if len(parts) >= 2:
                        name = parts[0]
                        status = parts[-2]
                        color = '\033[92m' if 'Up' in status else '\033[91m'  # Green/Red
                        print(f"  {color}{name:30} {status}\033[0m")
        else:
            print_info("No services found (might not be running)")
    else:
        print_error("Docker Compose command failed")
        
except Exception as e:
    print_error(f"Could not check Docker services: {e}")

print("\nChecking system resources...")
try:
    # CPU usage
    cpu_percent = psutil.cpu_percent(interval=1)
    cpu_color = '\033[92m' if cpu_percent < 70 else '\033[93m' if cpu_percent < 90 else '\033[91m'
    print(f"  CPU Usage: {cpu_color}{cpu_percent:.1f}%\033[0m")
    
    # Memory usage
    memory = psutil.virtual_memory()
    mem_color = '\033[92m' if memory.percent < 70 else '\033[93m' if memory.percent < 90 else '\033[91m'
    print(f"  Memory: {mem_color}{memory.percent:.1f}%\033[0m used "
          f"({memory.used / (1024**3):.1f} GB / {memory.total / (1024**3):.1f} GB)")
    
    # Disk usage
    disk = psutil.disk_usage('.')
    disk_color = '\033[92m' if disk.percent < 70 else '\033[93m' if disk.percent < 90 else '\033[91m'
    print(f"  Disk: {disk_color}{disk.percent:.1f}%\033[0m used "
          f"({disk.used / (1024**3):.1f} GB / {disk.total / (1024**3):.1f} GB)")
    
except Exception as e:
    print_error(f"Could not check system resources: {e}")

print("\n" + "=" * 50)
print("SERVICE ENDPOINTS")
print("=" * 50)
print("""
Grafana Dashboard:    http://localhost:3000
Jupyter Notebook:     http://localhost:8888
Prometheus Metrics:   http://localhost:9090
pgAdmin:              http://localhost:5050
PostgreSQL:           localhost:5432
""")

print("\n" + "=" * 50)
print("DEFAULT CREDENTIALS")
print("=" * 50)
print("""
Grafana:              admin / admin123
Jupyter:              token: designingdb
pgAdmin:              admin@designingdb.com / admin123
PostgreSQL:           admin / admin123
""")

wait_for_user()

# ============================================================================
# CELL 8: GENERATE TEST WORKLOAD
# ============================================================================

print_step(8, "Generating Test Workload")

print("\nCreating test data in the database...")

try:
    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()
    
    # Check if sample tables exist
    cursor.execute("""
        SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name = 'customers'
        );
    """)
    customers_exists = cursor.fetchone()[0]
    
    if not customers_exists:
        print_info("Creating sample tables...")
        
        # Create customers table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS customers (
                customer_id SERIAL PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                email VARCHAR(255) UNIQUE NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                status VARCHAR(20) DEFAULT 'active',
                region VARCHAR(50),
                credit_limit DECIMAL(10,2) DEFAULT 1000.00
            );
        """)
        
        # Create products table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS products (
                product_id SERIAL PRIMARY KEY,
                name VARCHAR(200) NOT NULL,
                category VARCHAR(100),
                price DECIMAL(10,2) NOT NULL,
                stock_quantity INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        
        conn.commit()
        print_success("Created sample tables")
    
    # Insert some test data
    print_info("Inserting test data...")
    
    # Insert customers
    customers = [
        ('John Doe', 'john@example.com', 'North', 1500.00),
        ('Jane Smith', 'jane@example.com', 'South', 2000.00),
        ('Bob Johnson', 'bob@example.com', 'East', 1200.00),
        ('Alice Brown', 'alice@example.com', 'West', 1800.00),
        ('Charlie Wilson', 'charlie@example.com', 'North', 2200.00)
    ]
    
    for customer in customers:
        cursor.execute("""
            INSERT INTO customers (name, email, region, credit_limit) 
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (email) DO NOTHING;
        """, customer)
    
    # Insert products
    products = [
        ('Laptop', 'Electronics', 999.99, 50),
        ('Smartphone', 'Electronics', 699.99, 100),
        ('Book', 'Books', 29.99, 200),
        ('Chair', 'Furniture', 149.99, 30),
        ('Coffee Mug', 'Kitchen', 9.99, 150)
    ]
    
    for product in products:
        cursor.execute("""
            INSERT INTO products (name, category, price, stock_quantity) 
            VALUES (%s, %s, %s, %s)
            ON CONFLICT DO NOTHING;
        """, product)
    
    conn.commit()
    print_success(f"Inserted {len(customers)} customers and {len(products)} products")
    
    # Run some queries to populate pg_stat_statements
    print_info("Running test queries to populate statistics...")
    
    test_queries = [
        "SELECT COUNT(*) FROM customers;",
        "SELECT * FROM customers WHERE region = 'North';",
        "SELECT name, email FROM customers ORDER BY name;",
        "SELECT category, AVG(price) FROM products GROUP BY category;",
        "UPDATE products SET stock_quantity = stock_quantity - 1 WHERE product_id = 1;",
        "INSERT INTO customers (name, email, region) VALUES ('Test User', 'test@example.com', 'Test');",
        "SELECT c.name, p.name FROM customers c CROSS JOIN products p LIMIT 10;",
        "EXPLAIN SELECT * FROM customers WHERE region = 'North';"
    ]
    
    for i, query in enumerate(test_queries, 1):
        try:
            cursor.execute(query)
            if query.strip().upper().startswith('SELECT'):
                cursor.fetchall()  # Consume results
            print(f"  Ran query {i}/{len(test_queries)}")
        except Exception as e:
            print(f"  Query {i} failed: {e}")
    
    # Get row counts
    cursor.execute("SELECT COUNT(*) FROM customers;")
    customer_count = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM products;")
    product_count = cursor.fetchone()[0]
    
    print_success(f"Database now has {customer_count} customers and {product_count} products")
    
    cursor.close()
    conn.close()
    
except Exception as e:
    print_error(f"Error generating test workload: {e}")

wait_for_user()

# ============================================================================
# CELL 9: NEXT STEPS AND CONCLUSION
# ============================================================================

print_step(9, "Next Steps and Conclusion")

print("\n" + "=" * 60)
print("DEMO COMPLETED SUCCESSFULLY!")
print("=" * 60)

print("""
You have successfully:

1. ✅ Set up the Python environment
2. ✅ Tested database connectivity
3. ✅ Generated sample data
4. ✅ Created visualizations
5. ✅ Tested monitoring modules
6. ✅ Checked system health
7. ✅ Created test workload

The Self-Designing Database System is now ready!
""")

print("\n" + "=" * 60)
print("NEXT STEPS TO EXPLORE THE SYSTEM")
print("=" * 60)

print("""
1. Explore Grafana Dashboard:
   Open http://localhost:3000 (admin/admin123)
   View pre-configured database performance dashboards

2. Start the Monitoring System:
   python -m src.monitoring.workload_monitor
   (Or run the monitor in the background)

3. Create Database Snapshots:
   python -c "
   from src.monitoring.db_inspector import DatabaseInspector
   inspector = DatabaseInspector({
       'host': 'localhost',
       'port': 5432,
       'database': 'self_designing_db',
       'user': 'admin',
       'password': 'admin123'
   })
   inspector.connect()
   snapshot = inspector.create_snapshot('demo')
   print(f'Snapshot: {snapshot[\"name\"]}')
   inspector.disconnect()
   "

4. Generate More Test Data:
   python generate_test_data.py
   (Creates more realistic workload patterns)

5. Explore the Database:
   Use pgAdmin at http://localhost:5050
   Login: admin@designingdb.com / admin123

6. View Raw Metrics:
   Check Prometheus at http://localhost:9090

7. Continue Development:
   - Implement RL Environment (Prompt 2)
   - Build RL Agent (Prompt 3)
   - Add Advanced Optimizations (Prompt 4)
""")

print("\n" + "=" * 60)
print("TROUBLESHOOTING TIPS")
print("=" * 60)

print("""
If you encounter issues:

1. Check Docker services:
   docker-compose ps
   docker-compose logs [service_name]

2. Restart services:
   docker-compose restart
   docker-compose up -d

3. Reset the system:
   docker-compose down -v
   docker-compose up -d

4. Check database:
   psql -h localhost -p 5432 -U admin -d self_designing_db

5. View generated files:
   - performance_dashboard.png
   - summary_charts.png
   - Check logs/ directory
""")

print("\n" + "=" * 60)
print("THANK YOU FOR RUNNING THE DEMO!")
print("=" * 60)

print("\nCreated files:")
print("1. performance_dashboard.png - Main visualization")
print("2. summary_charts.png - Summary pie charts")
print("3. demo_notebook.py - This interactive demo script")

print("\nThe system is now ready for the next prompts!")
print("You can proceed to implement the RL environment (Prompt 2).")