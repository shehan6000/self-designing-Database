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