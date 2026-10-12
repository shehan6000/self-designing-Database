# Self-Designing Database System
<img width="2369" height="1839" alt="performance_dashboard" src="https://github.com/user-attachments/assets/55baa25b-47a1-414d-95bb-272c1e2cc6de" />

##  Overview

This research project investigates autonomous database systems that eliminate manual tuning through continuous self-optimization. The system employs reinforcement learning to dynamically configure indexes, storage layouts, compression schemes, and partitioning strategies in response to evolving workloads, representing a paradigm shift from reactive DBA-driven tuning to proactive machine-driven optimization.

---



##  Technical Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────┐
│                   Workload Monitor                       │
│  • Query parser & feature extraction                     │
│  • Temporal pattern detection                            │
│  • Anomaly detection                                     │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│              RL Policy Engine (Agent)                    │
│  • State: workload features, current config, metrics    │
│  • Action: index creation/deletion, partition schemes    │
│  • Reward: query latency, throughput, resource usage    │
│  • Algorithm: Soft Actor-Critic / PPO / Model-based RL  │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│           Configuration Optimizer                        │
│  • Cost model integration                                │
│  • What-if analysis                                      │
│  • Safe action filtering                                 │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│           Database Execution Engine                      │
│  • PostgreSQL / MySQL / Custom Storage Engine           │
│  • Online schema modification                            │
│  • Metrics collection                                    │
└─────────────────────────────────────────────────────────┘
```

### State Representation

The RL agent observes a rich state space:

**Workload Features (W):**
- Query type distribution (SELECT, INSERT, UPDATE, DELETE)
- Access patterns (sequential, random, range scans)
- Selectivity histograms
- Join characteristics
- Temporal patterns (hourly, daily, seasonal)

**Configuration Features (C):**
- Active indexes: {columns, type (B-tree, hash, GiST), size}
- Partitioning: {strategy, key, count}
- Compression: {method (LZ4, Zstd, dictionary), ratio}
- Storage layout: {row-store, column-store, hybrid}

**Performance Metrics (P):**
- p50, p95, p99 query latency
- Throughput (QPS)
- Cache hit rate
- I/O operations
- CPU/memory utilization
- Storage footprint

**State Vector:** s_t = [W_t, C_t, P_t, Δ_t]

where Δ_t captures recent trends.

### Action Space

The agent selects from a hierarchical action space:

**Index Actions:**
- CREATE INDEX: {column_set, index_type, partial_predicate}
- DROP INDEX: {index_id}
- REBUILD INDEX: {index_id, parameters}

**Partitioning Actions:**
- REPARTITION: {strategy ∈ {range, hash, list}, key, num_partitions}
- MERGE_PARTITIONS: {partition_ids}
- PRUNE_PARTITIONS: {partition_ids}

**Compression Actions:**
- COMPRESS: {table, column, method, level}
- DECOMPRESS: {table, column}

**Storage Layout Actions:**
- CONVERT_LAYOUT: {table, layout ∈ {row, column, hybrid}}
- REORGANIZE: {table, clustering_key}

### Reward Function

Multi-objective reward balancing performance, cost, and stability:

```
R(s_t, a_t, s_{t+1}) = w_1 · R_latency + w_2 · R_throughput + w_3 · R_storage + w_4 · R_stability

where:
- R_latency = -normalize(p95_latency)
- R_throughput = normalize(QPS)
- R_storage = -normalize(storage_bytes)
- R_stability = -|C_{t+1} - C_t| (penalize excessive reconfiguration)
```

Dynamic weight adjustment based on SLA priorities.

---

## Machine Learning Methodology

### Reinforcement Learning Algorithm Selection

**Primary Approach: Soft Actor-Critic (SAC)**

Rationale:
- Sample efficiency critical for live systems
- Off-policy learning enables experience replay
- Entropy regularization encourages exploration
- Continuous action space compatibility (via discretization/parameterization)

**Alternative Approaches:**
- Proximal Policy Optimization (PPO): Better stability guarantees
- Model-Based RL (MBRL): Reduces real system interactions via learned dynamics
- Conservative Q-Learning (CQL): Safe offline RL from historical logs

### Workload Prediction Module

Anticipate future workloads to enable proactive optimization:

**Time Series Forecasting:**
- Temporal Convolutional Networks (TCN)
- Transformer models for long-range dependencies
- Seasonal ARIMA for periodic patterns

**Anomaly Detection:**
- Isolation Forest for workload shift detection
- One-Class SVM for outlier queries

### Cost Model Integration

Accurate performance prediction without executing queries:

- **PostgreSQL Explain Cost Model:** Leverage query optimizer estimates
- **Learned Cost Models:** Neural networks trained on (query, config) → latency mappings
- **What-If Analysis:** Hypothetical execution cost estimation

### Safe Exploration Strategies

Prevent catastrophic configurations in production:

1. **Constrained RL:** Hard constraints on configuration changes (max indexes, min throughput)
2. **Shadow Testing:** Validate actions on replicated shadow databases
3. **Gradual Rollout:** Canary deployments with automatic rollback
4. **Risk-Aware Policies:** Penalize high-variance actions

---

## Implementation Plan

### Technology Stack (All Open-Source)

**Database Layer:**
- PostgreSQL 16+ (primary testbed)
- MySQL 8.0+ (secondary validation)
- DuckDB (for analytical workload experiments)

**RL Framework:**
- Ray RLlib (distributed RL training)
- Stable-Baselines3 (algorithm implementations)
- Gymnasium (environment interface)

**Workload Generation:**
- OLTP-Bench (TPC-C, YCSB benchmarks)
- JOB (Join Order Benchmark) for analytics
- Custom workload synthesizers

**Observability:**
- Prometheus + Grafana (metrics collection)
- PostgreSQL pg_stat views
- perf / eBPF for deep profiling

**Infrastructure:**
- Docker + Docker Compose (reproducible environments)
- Kubernetes (optional, for distributed experiments)

**Data Science:**
- PyTorch (neural network components)
- Pandas / Polars (data analysis)
- Optuna (hyperparameter tuning)

## Experimental Design

### Benchmarks

**Standard Workloads:**
- TPC-C (OLTP)
- TPC-H (OLAP)
- YCSB variants (key-value patterns)
- JOB (complex joins)

**Dynamic Workloads:**
- Diurnal patterns (business hours vs off-hours)
- Workload shifts (OLTP → OLAP transition)
- Flash crowds (sudden traffic spikes)
- Schema evolution scenarios

### Baselines

1. **Static Optimal:** Manually tuned by expert DBA for initial workload
2. **PostgreSQL Auto-vacuum/Analyze:** Built-in adaptive features
3. **Heuristic Tuners:** Rule-based index advisors
4. **Existing ML Approaches:** OtterTune, CDBTune (if reproducible)

### Evaluation Metrics

**Performance:**
- Normalized query latency (vs optimal static)
- Throughput improvement percentage
- Time-to-adapt (workload shift → recovery)

**Efficiency:**
- Storage overhead
- Reconfiguration cost (downtime, CPU usage)
- Sample complexity (queries needed to learn)

**Robustness:**
- Performance under distribution shift
- Stability (configuration change frequency)
- Worst-case guarantees

### Ablation Studies

- Impact of each action type (indexes vs partitioning vs compression)
- Reward function component sensitivity
- Cost model accuracy requirements
- Exploration strategy effectiveness

---





