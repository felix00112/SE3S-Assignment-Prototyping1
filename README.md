# SE3S Assignment Prototyping 1

This repository contains the prototype setup for the Scalability Engineering prototyping assignment.

The folder structure is now aligned with the selected reservation-system architecture based on Nginx, FastAPI replicas, Redis rate limiting, an admission gate, a Redis booking queue, worker cells, an atomic Redis Lua script, and a reservation status endpoint.
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

Current compose-backed services:

```text
api
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

The application itself should still be started through Docker Compose during development, because Redis is provided as a Docker container.

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
docker compose logs redis
```

## Current Endpoints

```text
GET /
GET /health
GET /redis-test
```

## Architecture-Oriented Folder Layout

```text
gateway/nginx
services/api
workers/cells
workers/cleanup              # optional
infrastructure/redis
tests/k6
tests/locust                 # optional
docs/architecture
```
