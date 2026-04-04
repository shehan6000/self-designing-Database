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