#!/bin/bash
# Health check script for Self-Designing Database System

set -e

echo "Performing health checks..."

# Check Docker services
echo "1. Checking Docker services..."
if docker-compose ps | grep -q "Up"; then
    echo "âœ“ All Docker services are running"
else
    echo "âœ— Some Docker services are not running"
    docker-compose ps
    exit 1
fi

# Check PostgreSQL
echo "2. Checking PostgreSQL..."
if docker exec self-designing-postgres pg_isready -U admin -d self_designing_db; then
    echo "âœ“ PostgreSQL is ready"
else
    echo "âœ— PostgreSQL is not ready"
    exit 1
fi

# Check Prometheus
echo "3. Checking Prometheus..."
if curl -s http://localhost:9090/-/healthy > /dev/null; then
    echo "âœ“ Prometheus is healthy"
else
    echo "âœ— Prometheus is not responding"
    exit 1
fi

# Check Grafana
echo "4. Checking Grafana..."
if curl -s http://localhost:3000/api/health > /dev/null; then
    echo "âœ“ Grafana is healthy"
else
    echo "âœ— Grafana is not responding"
    exit 1
fi

# Check Postgres Exporter
echo "5. Checking Postgres Exporter..."
if curl -s http://localhost:9187/metrics > /dev/null; then
    echo "âœ“ Postgres Exporter is healthy"
else
    echo "âœ— Postgres Exporter is not responding"
    exit 1
fi

echo ""
echo "All health checks passed! âœ…"
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