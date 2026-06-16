# SE3S Assignment Prototyping 1

This repository contains the initial prototype setup for the Scalability Engineering prototyping assignment.

The final application domain is still under discussion. The current setup is intentionally generic and provides a minimal scalable backend foundation using FastAPI, PostgreSQL, Redis, and Docker Compose.
## Getting Started

### Prerequisites

Make sure the following tools are installed:

```bash
Python >= 3.11
Docker
Docker Compose
Git
```

Optional:

```bash
PyCharm or VS Code
GitHub CLI
```

### Clone Repository

```bash
git clone https://github.com/felix00112/SE3S-Assignment-Prototyping1.git
cd SE3S-Assignment-Prototyping1
```

### Start Application with Docker Compose

```bash
docker compose up --build
```

Or run it in detached mode:

```bash
docker compose up -d --build
```

### Check Running Containers

```bash
docker compose ps
```

Expected services:

```text
api
postgres
redis
```

### Access API

```text
http://localhost:8000
```

### Access FastAPI Documentation

```text
http://localhost:8000/docs
```

## Development Setup

Create a virtual environment:

```bash
python -m venv .venv
```

Activate the virtual environment:

```bash
source .venv/bin/activate
```

Install dependencies:

```bash
pip install -r requirements.txt
```

The application itself should still be started through Docker Compose during development, because PostgreSQL and Redis are provided as Docker containers.

## PostgreSQL

Connect to PostgreSQL through Docker:

```bash
docker compose exec postgres psql -U postgres -d scaling_app
```

The PostgreSQL database can be accessed through any IDE or database client using the following connection settings:

```text
Host: localhost
Port: 5432
User: postgres
Password: postgres
Database: scaling_app
```

## Redis

Connect to Redis:

```bash
docker compose exec redis redis-cli
```

Test Redis:

```redis
PING
```

Expected response:

```text
PONG
```

## Useful Commands

Rebuild and start all services:

```bash
docker compose up --build
```

Start services in the background:

```bash
docker compose up -d
```

Stop services:

```bash
docker compose down
```

Stop services and remove database volume:

```bash
docker compose down -v
```

View logs:

```bash
docker compose logs api
docker compose logs postgres
docker compose logs redis
```

## Current Endpoints

```text
GET /
GET /health
GET /redis-test
```

## Current Project Status

The project currently contains a generic backend setup with FastAPI, PostgreSQL, Redis, and Docker Compose.

The final application domain is still under discussion. Possible options are:

```text
Flash-sale ticket reservation system
Scalable quiz / answer processing platform
```
