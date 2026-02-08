# Self-Designing Database System

A complete Docker-based development environment for a self-designing database system with PostgreSQL 16, featuring automated index optimization through reinforcement learning.

## System Architecture
┌─────────────────────────────────────────────────────────────┐
│ Application Layer │
├─────────────────────────────────────────────────────────────┤
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│ │ Jupyter │ │ Grafana │ │ pgAdmin │ │ Custom │ │
│ │ Lab │ │ Dash- │ │ │ │ Apps │ │
│ │ │ │ boards │ │ │ │ │ │
│ └──────────┘ └──────────┘ └──────────┘ └──────────┘ │
├─────────────────────────────────────────────────────────────┤
│ Monitoring & Analytics │
├─────────────────────────────────────────────────────────────┤
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│ │Workload │ │Database │ │ Feature │ │Prometheus│ │
│ │Monitor │ │Inspector │ │Extractor │ │ Exporter │ │
│ └──────────┘ └──────────┘ └──────────┘ └──────────┘ │
├─────────────────────────────────────────────────────────────┤
│ Reinforcement Learning │
├─────────────────────────────────────────────────────────────┤
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│ │ RL │ │ Safe │ │ Cost │ │ Shadow │ │
│ │ Agent │ │ Action │ │ Model │ │ Testing │ │
│ │ (SAC) │ │Executor │ │ │ │ │ │
│ └──────────┘ └──────────┘ └──────────┘ └──────────┘ │
├─────────────────────────────────────────────────────────────┤
│ Database Layer │
├─────────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────────┐ │
│ │ PostgreSQL 16 with Extensions │ │
│ │ • pg_stat_statements • pg_partman • auto_explain │ │
│ └──────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

text

## Features

### 1. Foundational Infrastructure & Monitoring
- **PostgreSQL 16** with monitoring extensions
- **Prometheus** for metrics collection
- **Grafana** with pre-configured dashboards
- **Jupyter Lab** with ML dependencies
- **Workload Monitoring System** with real-time metrics
- **Database State Inspector** for configuration snapshots
- **Feature Extraction Pipeline** for RL state vectors

### 2. Reinforcement Learning Environment
- **Gymnasium Environment** for database optimization
- **Safe Action Executor** with validation
- **Cost Model** for hypothetical index analysis
- **Shadow Testing Framework** for safe deployments

### 3. RL Agent & Training System
- **Soft Actor-Critic (SAC)** agent implementation
- **Training Pipeline** with parallel environments
- **Benchmark Workloads** (TPC-C, YCSB, custom)
- **Evaluation Framework** with statistical analysis

### 4. Advanced Optimizations
- **Expanded Action Space** (partitioning, compression, storage layout)
- **Workload Prediction Module** with TCN forecasting
- **Production Hardening** with gradual rollout
- **Ablation Studies** for component analysis

## Quick Start

### Prerequisites
- Docker and Docker Compose
- Python 3.11+
- 8GB+ RAM recommended

### Installation

1. **Clone and setup:**
```bash
git clone <repository-url>
cd SelfDesigningDB
chmod +x setup.sh
./setup.sh
