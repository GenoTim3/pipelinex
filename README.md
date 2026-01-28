# PipelineX

A lightweight CI/CD pipeline runner that integrates with GitHub and executes pipeline steps in isolated containers on Kubernetes.

## Overview

PipelineX listens for GitHub webhooks, parses pipeline configuration files from your repositories, and orchestrates containerized build steps on a Kubernetes cluster.

## Architecture

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   GitHub    │──────│  Webhook    │──────│    Redis    │
│  (webhook)  │      │    API      │      │   (queue)   │
└─────────────┘      └─────────────┘      └──────┬──────┘
                                                  │
                     ┌─────────────┐      ┌──────▼──────┐
                     │  Dashboard  │◄─────│ Controller  │
                     │   (React)   │      │  (worker)   │
                     └─────────────┘      └──────┬──────┘
                                                  │
                     ┌─────────────┐      ┌──────▼──────┐
                     │  Postgres   │◄─────│ Kubernetes  │
                     │    (db)     │      │   (jobs)    │
                     └─────────────┘      └─────────────┘
```

## Components

| Component | Description | Tech |
|-----------|-------------|------|
| API | Receives GitHub webhooks, parses pipelines, queues jobs | Python / FastAPI |
| Controller | Pulls jobs from queue, creates K8s jobs, tracks status | Python |
| Dashboard | Displays pipeline runs, statuses, and logs | React |
| Queue | Decouples API from controller | Redis |
| Database | Stores pipeline runs and logs | PostgreSQL |

## Pipeline Configuration

Create a `.pipeline.yml` file in your repository root:

```yaml
name: Build and Test
steps:
  - name: Install dependencies
    image: node:18
    commands:
      - npm install

  - name: Run tests
    image: node:18
    commands:
      - npm test

  - name: Build
    image: node:18
    commands:
      - npm run build
```

## Getting Started

### Prerequisites

- **Docker Desktop** with Kubernetes enabled
  - Open Docker Desktop → Settings → Kubernetes → Enable Kubernetes
- **Python 3.11** (3.13 has compatibility issues with some packages)
- **kubectl** CLI tool
- **Git**

### Verify Prerequisites

```bash
# Check Docker
docker --version

# Check Kubernetes is running
kubectl cluster-info

# Check Python version (needs 3.11)
python3.11 --version
```

### Installation & Setup

#### Step 1: Clone and Enter Project

```bash
git clone https://github.com/yourusername/pipelinex.git
cd pipelinex
```

#### Step 2: Create Kubernetes Namespace

```bash
kubectl apply -f k8s/manifests/namespace.yaml
```

#### Step 3: Start Infrastructure (Terminal 1)

```bash
docker-compose up postgres redis api
```

Wait until you see:
```
api-1  | INFO:     Uvicorn running on http://0.0.0.0:8000
```

#### Step 4: Start Controller (Terminal 2)

```bash
cd ~/path/to/pipelinex

# Create Python virtual environment with Python 3.11
python3.11 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r controller/requirements.txt

# Set environment variables
export DATABASE_URL=postgresql://pipelinex:pipelinex@127.0.0.1:5432/pipelinex
export REDIS_URL=redis://127.0.0.1:6379/0
export K8S_NAMESPACE=pipelinex
export PYTHONPATH=$(pwd)

# Run controller
python -m controller.src.main
```

Wait until you see:
```
Worker started, waiting for jobs...
```

#### Step 5: Verify Everything is Running

```bash
# Check API health
curl http://localhost:8000/health/all

# Check Kubernetes namespace
kubectl get namespace pipelinex
```

### Testing the Pipeline

#### Option 1: Manual Webhook Test

```bash
curl -X POST http://localhost:8000/api/webhooks/github \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -d '{
    "ref": "refs/heads/main",
    "repository": {
      "name": "your-repo",
      "full_name": "your-username/your-repo",
      "clone_url": "https://github.com/your-username/your-repo.git"
    },
    "head_commit": {
      "id": "YOUR_COMMIT_SHA",
      "message": "Test commit"
    },
    "pusher": {
      "name": "testuser"
    }
  }'
```

#### Option 2: Real GitHub Webhook

1. Go to your repository's **Settings → Webhooks**
2. Click **Add webhook**
3. Set Payload URL: `https://your-domain.com/api/webhooks/github`
4. Set Content type: `application/json`
5. Select **Just the push event**
6. Click **Add webhook**

> **Note:** For local development, use a tool like [ngrok](https://ngrok.com/) to expose your local API.

### Checking Pipeline Status

```bash
# View running jobs
kubectl get jobs -n pipelinex

# View pods
kubectl get pods -n pipelinex

# View logs from a specific run
kubectl logs -n pipelinex -l run-id=YOUR_RUN_ID

# Check pipeline runs via API
curl http://localhost:8000/api/pipelines/runs
```

## Troubleshooting

### Common Issues

#### 1. "role pipelinex does not exist" Error

**Cause:** A local PostgreSQL installation is intercepting port 5432 before Docker's Postgres.

**Solution:**
```bash
# Check what's using port 5432
lsof -i :5432

# If you see a local postgres process, stop it:
brew services stop postgresql
brew services stop postgresql@14
brew services stop postgresql@15

# Or kill it directly (replace PID with actual process ID)
kill -9 <PID>

# Verify only Docker is using the port
lsof -i :5432
# Should only show "com.docke" process
```

#### 2. "Connection refused" to Redis

**Cause:** Docker containers aren't running.

**Solution:**
```bash
# Make sure Docker containers are running in Terminal 1
docker-compose up postgres redis api
```

#### 3. Controller Can't Connect to Kubernetes

**Cause:** Kubernetes not enabled in Docker Desktop or kubeconfig not set up.

**Solution:**
```bash
# Check if Kubernetes is running
kubectl cluster-info

# If not, enable it in Docker Desktop:
# Docker Desktop → Settings → Kubernetes → Enable Kubernetes → Apply & Restart

# Verify kubeconfig exists
cat ~/.kube/config | grep server
```

#### 4. Python Package Build Errors (asyncpg, psycopg2)

**Cause:** Using Python 3.13 which has compatibility issues.

**Solution:**
```bash
# Use Python 3.11 instead
brew install python@3.11

# Recreate virtual environment
rm -rf venv
python3.11 -m venv venv
source venv/bin/activate
pip install -r controller/requirements.txt
```

#### 5. "No pipeline configuration found"

**Cause:** The `.pipeline.yml` file doesn't exist or is named incorrectly.

**Solution:**
- File must be named exactly `.pipeline.yml` (with leading dot)
- File must be in the repository root
- Commit SHA in webhook must be from a commit where the file exists

#### 6. VS Code Shows Thousands of Untracked Files

**Cause:** VS Code cached state from before `.gitignore` was created.

**Solution:**
```bash
# In VS Code: Cmd + Shift + P → "Reload Window"

# Or clear VS Code workspace cache
rm -rf ~/Library/Application\ Support/Code/User/workspaceStorage/*
```

#### 7. Webhook Returns "Failed to clone repository"

**Cause:** Invalid commit SHA or private repository.

**Solution:**
- Ensure commit SHA exists in the repository
- For private repos, configure GitHub authentication (not yet implemented)

### Useful Commands

```bash
# View all Docker containers
docker ps

# View Docker logs
docker-compose logs -f api

# Restart all containers
docker-compose down && docker-compose up

# Clean up Kubernetes jobs
kubectl delete jobs --all -n pipelinex

# Check API endpoints
curl http://localhost:8000/docs  # Swagger UI
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | API health check |
| `/health/db` | GET | Database health check |
| `/health/redis` | GET | Redis health check |
| `/health/all` | GET | Full system health check |
| `/api/webhooks/github` | POST | GitHub webhook receiver |
| `/api/pipelines/runs` | GET | List all pipeline runs |
| `/api/pipelines/runs/{id}` | GET | Get specific run details |
| `/api/pipelines/runs/{id}/logs` | GET | Get run logs |
| `/api/pipelines/stats` | GET | Pipeline statistics |

## Project Structure

```
pipelinex/
├── api/                 # Webhook API service (FastAPI)
│   ├── src/
│   │   ├── routes/      # API endpoints
│   │   ├── services/    # Business logic
│   │   ├── models/      # Database models
│   │   └── db/          # Database connection
│   └── Dockerfile
├── controller/          # Pipeline execution controller
│   ├── src/
│   │   ├── k8s/         # Kubernetes client & job builder
│   │   ├── services/    # Executor, log collector, status reporter
│   │   └── models/      # Data models
│   └── Dockerfile
├── dashboard/           # React frontend (Phase 4)
├── db/                  # Database migrations
├── helm/                # Helm charts for K8s deployment
├── k8s/                 # Kubernetes manifests
├── scripts/             # Setup scripts
└── docs/                # Documentation
```

## Roadmap

- [x] Webhook API with GitHub integration
- [x] Pipeline YAML parser
- [x] Redis job queue
- [x] Kubernetes job execution
- [x] Log collection
- [x] Status reporting
- [ ] Dashboard UI
- [ ] Real-time log streaming
- [ ] Parallel step execution
- [ ] Pipeline caching
- [ ] Multi-repo support
- [ ] GitHub App authentication

## Contributing

Contributions are welcome! Please read the contributing guidelines before submitting a PR.

## License

MIT License - see LICENSE file for details.