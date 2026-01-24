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

Create a `.pipeline.yml` file in your repository:

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

- Docker & Docker Compose
- Kubernetes cluster (or minikube/kind for local development)
- GitHub account (for webhook integration)

### Local Development

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/pipelinex.git
   cd pipelinex
   ```

2. Copy environment variables:
   ```bash
   cp .env.example .env
   ```

3. Start the local Kubernetes cluster:
   ```bash
   ./scripts/create-kind-cluster.sh
   ```

4. Run with Docker Compose:
   ```bash
   docker-compose up --build
   ```

5. Access the dashboard at `http://localhost:3000`

### GitHub Webhook Setup

1. Go to your repository's Settings → Webhooks
2. Add webhook URL: `https://your-domain.com/api/webhooks/github`
3. Set content type to `application/json`
4. Select "Just the push event"
5. Add your webhook secret to `.env`

## Project Structure

```
pipelinex/
├── api/                 # Webhook API service
├── controller/          # Pipeline execution controller
├── dashboard/           # React frontend
├── db/                  # Database migrations
├── helm/                # Helm charts for K8s deployment
├── k8s/                 # Kubernetes manifests
├── scripts/             # Utility scripts
└── docs/                # Documentation
```

## Deployment

### Using Helm

```bash
helm install pipelinex ./helm/pipelinex -n pipelinex --create-namespace
```

### Using kubectl

```bash
kubectl apply -f k8s/manifests/
```

## Roadmap

- [ ] Webhook API with GitHub integration
- [ ] Pipeline YAML parser
- [ ] Kubernetes job execution
- [ ] Real-time log streaming
- [ ] Dashboard UI
- [ ] Parallel step execution
- [ ] Pipeline caching
- [ ] Multi-repo support

## Contributing

Contributions are welcome! Please read the contributing guidelines before submitting a PR.

## License

MIT License - see LICENSE file for details.