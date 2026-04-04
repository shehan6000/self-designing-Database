# Setup script for Self-Designing Database System (Windows)

Write-Host "Setting up Self-Designing Database System for Windows..." -ForegroundColor Green

# Check if Python 3.11 is installed
Write-Host "Checking Python installation..." -ForegroundColor Yellow
$pythonVersion = python --version 2>$null
if (-not $pythonVersion -or $pythonVersion -notmatch "Python 3\.11") {
    Write-Host "Python 3.11 is required. Please install from https://www.python.org/downloads/" -ForegroundColor Red
    Write-Host "Make sure to check 'Add Python to PATH' during installation" -ForegroundColor Yellow
    exit 1
}
Write-Host " Python found: $pythonVersion" -ForegroundColor Green

# Check if Docker is running
Write-Host "Checking Docker..." -ForegroundColor Yellow
try {
    $dockerVersion = docker --version
    $dockerComposeVersion = docker-compose --version
    Write-Host " Docker found: $dockerVersion" -ForegroundColor Green
    Write-Host " Docker Compose found: $dockerComposeVersion" -ForegroundColor Green
} catch {
    Write-Host "Docker is not running or not installed. Please install Docker Desktop from https://www.docker.com/products/docker-desktop/" -ForegroundColor Red
    exit 1
}

# Check Docker daemon
Write-Host "Checking Docker daemon..." -ForegroundColor Yellow
try {
    docker ps > $null 2>&1
    Write-Host " Docker daemon is running" -ForegroundColor Green
} catch {
    Write-Host "Docker daemon is not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}

# Create virtual environment
Write-Host "Creating virtual environment..." -ForegroundColor Yellow
if (Test-Path "venv") {
    Write-Host "Virtual environment already exists, skipping..." -ForegroundColor Yellow
} else {
    python -m venv venv
    Write-Host " Virtual environment created" -ForegroundColor Green
}

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Yellow
$activateScript = ".\venv\Scripts\Activate.ps1"
if (Test-Path $activateScript) {
    . $activateScript
    Write-Host " Virtual environment activated" -ForegroundColor Green
} else {
    Write-Host "Failed to find activation script. Activating manually..." -ForegroundColor Yellow
    $env:VIRTUAL_ENV = "$PWD\venv"
    $env:PATH = "$PWD\venv\Scripts;$env:PATH"
}

# Upgrade pip
Write-Host "Upgrading pip..." -ForegroundColor Yellow
python -m pip install --upgrade pip
Write-Host " Pip upgraded" -ForegroundColor Green

# Install dependencies
Write-Host "Installing dependencies..." -ForegroundColor Yellow
pip install -r requirements.txt
Write-Host " Dependencies installed" -ForegroundColor Green

# Install the package in development mode
Write-Host "Installing package in development mode..." -ForegroundColor Yellow
pip install -e .
Write-Host " Package installed" -ForegroundColor Green

# Create necessary directories
Write-Host "Creating directories..." -ForegroundColor Yellow
$directories = @("data\snapshots", "data\models", "logs", "tests\data")
foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-Host "  Created: $dir" -ForegroundColor Gray
    }
}
Write-Host " Directories created" -ForegroundColor Green

# Initialize git if not already
Write-Host "Checking git repository..." -ForegroundColor Yellow
if (-not (Test-Path ".git")) {
    Write-Host "Initializing git repository..." -ForegroundColor Yellow
    git init
    git add .
    git commit -m "Initial commit: Self-Designing Database System"
    Write-Host " Git repository initialized" -ForegroundColor Green
} else {
    Write-Host "Git repository already exists" -ForegroundColor Yellow
}

# Set execution policy for scripts
Write-Host "Setting execution policy for scripts..." -ForegroundColor Yellow
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-Host " Execution policy set" -ForegroundColor Green
} catch {
    Write-Host "Note: Could not set execution policy. You may need to run scripts differently." -ForegroundColor Yellow
}

Write-Host "`n=== SETUP COMPLETE ===" -ForegroundColor Green -BackgroundColor Black
Write-Host "`nTo start the system:" -ForegroundColor Cyan
Write-Host "1. Start Docker Compose: docker-compose up -d" -ForegroundColor White
Write-Host "2. Activate virtual environment: .\venv\Scripts\Activate" -ForegroundColor White
Write-Host "3. Run monitoring: python -m src.monitoring.workload_monitor" -ForegroundColor White
Write-Host "`nAccess services:" -ForegroundColor Cyan
Write-Host "- Grafana: http://localhost:3000 (admin/admin123)" -ForegroundColor White
Write-Host "- Jupyter: http://localhost:8888 (token: designingdb)" -ForegroundColor White
Write-Host "- PostgreSQL: localhost:5432 (admin/admin123)" -ForegroundColor White
Write-Host "- pgAdmin: http://localhost:5050 (admin@designingdb.com/admin123)" -ForegroundColor White
Write-Host "`nQuick commands:" -ForegroundColor Cyan
Write-Host "Start all: docker-compose up -d" -ForegroundColor White
Write-Host "Stop all: docker-compose down" -ForegroundColor White
Write-Host "View logs: docker-compose logs -f" -ForegroundColor White
Write-Host "`nFor help with Docker, ensure Docker Desktop is running and you have WSL 2 enabled for best performance." -ForegroundColor Yellow
