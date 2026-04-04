# Self-Designing Database System

A complete Docker-based development environment for a self-designing database system with PostgreSQL 16, featuring automated index optimization through reinforcement learning.

## 🚀 Quick Start

### Prerequisites
- Docker and Docker Compose
- Python 3.11+
- 8GB+ RAM recommended

### Installation

1. **Clone and setup:**
```bash
# Run the setup script (Windows)
.\setup.ps1

# Or manually:
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
```

2. **Start all services:**
```bash
docker-compose up -d
```

3. **Run health check:**
```bash
python health_check.py
```

4. **Access services:**
   - **Grafana**: http://localhost:3000 (admin/admin123)
   - **Jupyter**: http://localhost:8888 (token: designingdb)
   - **PostgreSQL**: localhost:5432 (admin/admin123)
   - **pgAdmin**: http://localhost:5050 (admin@designingdb.com/admin123)
   - **Prometheus**: http://localhost:9090

## 📊 System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                        │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ Jupyter  │  │ Grafana  │  │ pgAdmin  │  │  Custom  │   │
│  │  Lab     │  │ Dash-    │  │          │  │  Apps    │   │
│  │          │  │  boards  │  │          │  │          │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    Monitoring & Analytics                   │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │Workload  │  │Database  │  │ Feature  │  │Prometheus│   │
│  │Monitor   │  │Inspector │  │Extractor │  │ Exporter │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    Reinforcement Learning                   │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  RL      │  │  Safe    │  │  Cost    │  │  Shadow  │   │
│  │ Agent    │  │  Action  │  │  Model   │  │  Testing │   │
│  │  (SAC)   │  │Executor  │  │          │  │          │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    Database Layer                           │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐   │
│  │              PostgreSQL 16 with Extensions           │   │
│  │  • pg_stat_statements • pg_partman • auto_explain    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 🎯 Features

### ✅ Prompt 1: Foundational Infrastructure & Monitoring (COMPLETE)
- **PostgreSQL 16** with monitoring extensions
- **Prometheus** for metrics collection
- **Grafana** with pre-configured dashboards
- **Jupyter Lab** with ML dependencies
- **Workload Monitoring System** with real-time metrics
- **Database State Inspector** for configuration snapshots
- **Feature Extraction Pipeline** for RL state vectors

### 🔄 Prompt 2: RL Environment & Safety Layer (READY TO IMPLEMENT)
- Gymnasium environment wrapper
- Safe action executor with validation
- Cost model for hypothetical index analysis
- Shadow testing framework

### 🔄 Prompt 3: RL Agent & Training System (READY TO IMPLEMENT)
- Soft Actor-Critic (SAC) agent
- Training pipeline with parallel environments
- Benchmark workloads (TPC-C, YCSB)
- Evaluation framework

### 🔄 Prompt 4: Advanced Optimizations (READY TO IMPLEMENT)
- Expanded action space (partitioning, compression)
- Workload prediction with TCN forecasting
- Production hardening and deployment
- Ablation studies

## 📁 Project Structure

```
SelfDesigningDB/
├── docker/                    # Docker configurations
│   ├── postgres/             # PostgreSQL configs
│   ├── prometheus/           # Prometheus configs
│   └── postgres-exporter/    # Exporter queries
├── src/                      # Source code
│   ├── monitoring/           # Monitoring modules
│   │   ├── workload_monitor.py    # Real-time workload monitoring
│   │   └── db_inspector.py        # Database state inspection
│   ├── feature_extractor/    # Feature extraction
│   │   └── pipeline.py            # RL state vector extraction
│   ├── rl_env/              # RL environment (Prompt 2)
│   ├── rl_agent/            # RL agent (Prompt 3)
│   └── optimization/         # Advanced features (Prompt 4)
├── grafana/                  # Grafana dashboards
├── notebooks/                # Jupyter notebooks
│   ├── demo_monitoring.ipynb     # Monitoring system demo
│   ├── working_demo.ipynb        # Working demo notebook
│   └── simple_test.ipynb         # Basic test notebook
├── scripts/                  # Utility scripts
├── tests/                    # Test suite
├── docker-compose.yml        # Main Docker compose
├── requirements.txt          # Python dependencies
├── Makefile                  # Development commands
├── setup.ps1                 # Windows setup script
├── setup.sh                  # Linux/Mac setup script
├── demo.py                   # Complete demo script
├── demo_notebook.py          # Interactive notebook-style demo
└── README.md                 # This file
```

## 🛠️ Usage

### Basic Commands

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# Check service status
docker-compose ps

# View logs
docker-compose logs -f

# Run demo
python demo.py

# Generate test data
python generate_test_data.py

# Start monitoring
python -m src.monitoring.workload_monitor
```

### Database Operations

```bash
# Connect to PostgreSQL
psql -h localhost -p 5432 -U admin -d self_designing_db

# Create snapshot
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
print(f'Snapshot created: {snapshot[\"name\"]}')
inspector.disconnect()
"
```

### Development Commands

```bash
# Run tests
pytest tests/

# Format code
black src/ tests/ scripts/

# Lint code
flake8 src/ tests/ scripts/

# Type checking
mypy src/
```

## 📈 Monitoring Dashboard

The Grafana dashboard includes:
- **Database Connections**: Current active connections
- **Query Execution Time**: Performance over time
- **Cache Hit Ratio**: Buffer cache efficiency
- **Index Usage**: Index scan patterns
- **Query Type Distribution**: Read/write ratios
- **Table Access Patterns**: Hot table identification
- **Transaction Rate**: Throughput monitoring
- **Dead Tuples**: Vacuum monitoring

## 🔧 Feature Extraction

The system extracts three types of features:

### 1. Workload Features
- Query type distribution
- Temporal patterns (hourly/daily)
- Table access frequency
- Index usage patterns
- Latency percentiles (p50, p95, p99)
- Throughput and cache hit ratios

### 2. Configuration Features
- Index statistics (count, coverage, size)
- Table statistics (row counts, bloat factor)
- Schema characteristics
- Database configuration parameters

### 3. Performance Features
- Latency statistics
- Throughput metrics
- Resource utilization (CPU, memory, disk)
- Quality metrics (error rate, timeout rate)

## 🤖 Reinforcement Learning Integration

### State Space
- 256-dimensional normalized feature vector
- Combines workload, configuration, and performance features
- Updated every 30 seconds

### Action Space
- **CREATE INDEX**: Add new indexes
- **DROP INDEX**: Remove unused indexes
- **REBUILD INDEX**: Optimize existing indexes

### Reward Function
```
R = w1*(-latency_p95) + w2*throughput + w3*(-storage) + w4*(-config_changes)
```

## 🚀 Next Steps

### Prompt 2: RL Environment & Safety Layer
1. Implement Gymnasium environment wrapper
2. Create safe action executor
3. Build cost prediction model
4. Implement shadow testing framework

### Prompt 3: RL Agent & Training System
1. Implement SAC agent
2. Build training pipeline
3. Create benchmark workloads
4. Develop evaluation framework

### Prompt 4: Advanced Optimizations
1. Expand action space (partitioning, compression)
2. Implement workload prediction
3. Add production hardening
4. Create deployment artifacts

## 🐛 Troubleshooting

### Common Issues

1. **Port conflicts**:
```bash
# Check what's using ports
netstat -ano | findstr :5432  # Windows
lsof -i :5432  # Linux/Mac
```

2. **Docker not running**:
   - Start Docker Desktop
   - Check: `docker --version`

3. **Permission issues** (Linux/Mac):
```bash
sudo usermod -aG docker $USER
# Log out and back in
```

4. **Reset everything**:
```bash
docker-compose down -v
docker system prune -f
docker-compose up -d
```

### Service Logs
```bash
# View all logs
docker-compose logs

# View specific service logs
docker-compose logs postgres
docker-compose logs grafana
docker-compose logs jupyter
```

## 📝 License

MIT License - see LICENSE file for details.

## 🙏 Acknowledgments

- PostgreSQL Global Development Group
- Prometheus and Grafana communities
- OpenAI Gymnasium and Stable-Baselines3 teams
- All contributors and testers

---

