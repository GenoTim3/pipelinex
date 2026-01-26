#!/bin/bash

# PipelineX Phase 2 Setup Script
# Webhook + Queue Implementation
# Run from the pipelinex root directory

set -e

echo "🚀 Setting up Phase 2: Webhooks + Queue"

# ============================================
# Updated GitHub Service
# ============================================
cat > api/src/services/github.py << 'EOF'
"""
GitHub service for webhook validation and repo operations.
"""

import hmac
import hashlib
import tempfile
import subprocess
import os
from typing import Optional, Dict, Any

import httpx
import yaml

from api.src.config import get_settings

settings = get_settings()

def verify_signature(payload: bytes, signature: str) -> bool:
    """Verify GitHub webhook signature."""
    if not settings.github_webhook_secret:
        # Skip verification if no secret configured (development)
        return True
    
    expected = "sha256=" + hmac.new(
        settings.github_webhook_secret.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)

async def clone_repository(clone_url: str, commit_sha: str) -> str:
    """
    Clone repository to temporary directory.
    Returns path to cloned repo.
    """
    temp_dir = tempfile.mkdtemp(prefix="pipelinex_")
    repo_path = os.path.join(temp_dir, "repo")
    
    try:
        # Clone the repository
        subprocess.run(
            ["git", "clone", "--depth", "1", clone_url, repo_path],
            check=True,
            capture_output=True,
            timeout=120
        )
        
        # Checkout specific commit if provided
        if commit_sha:
            subprocess.run(
                ["git", "fetch", "--depth", "1", "origin", commit_sha],
                cwd=repo_path,
                capture_output=True,
                timeout=60
            )
            subprocess.run(
                ["git", "checkout", commit_sha],
                cwd=repo_path,
                check=True,
                capture_output=True,
                timeout=30
            )
        
        return repo_path
    except subprocess.TimeoutExpired:
        raise Exception("Repository clone timed out")
    except subprocess.CalledProcessError as e:
        raise Exception(f"Failed to clone repository: {e.stderr.decode()}")

async def fetch_pipeline_config(repo_path: str) -> Optional[Dict[str, Any]]:
    """
    Read .pipeline.yml from repository.
    Returns parsed config or None if not found.
    """
    config_paths = [
        os.path.join(repo_path, ".pipeline.yml"),
        os.path.join(repo_path, ".pipeline.yaml"),
        os.path.join(repo_path, "pipeline.yml"),
        os.path.join(repo_path, "pipeline.yaml"),
    ]
    
    for config_path in config_paths:
        if os.path.exists(config_path):
            with open(config_path, "r") as f:
                return yaml.safe_load(f)
    
    return None

def parse_webhook_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Extract relevant info from GitHub webhook payload."""
    repo = payload.get("repository", {})
    head_commit = payload.get("head_commit", {})
    
    # Get branch from ref (refs/heads/main -> main)
    ref = payload.get("ref", "")
    branch = ref.replace("refs/heads/", "") if ref.startswith("refs/heads/") else ref
    
    return {
        "repo_name": repo.get("name", ""),
        "repo_full_name": repo.get("full_name", ""),
        "clone_url": repo.get("clone_url", ""),
        "commit_sha": head_commit.get("id", payload.get("after", "")),
        "branch": branch,
        "commit_message": head_commit.get("message", ""),
        "pusher": payload.get("pusher", {}).get("name", ""),
    }

def cleanup_repo(repo_path: str):
    """Clean up cloned repository."""
    import shutil
    try:
        if repo_path and os.path.exists(repo_path):
            # Get parent temp directory
            parent = os.path.dirname(repo_path)
            shutil.rmtree(parent)
    except Exception:
        pass  # Best effort cleanup
EOF

echo "✅ api/src/services/github.py"

# ============================================
# Updated Pipeline Parser
# ============================================
cat > api/src/services/pipeline_parser.py << 'EOF'
"""
Pipeline YAML parser and validator.
"""

import yaml
from typing import List, Dict, Any, Optional

class PipelineConfigError(Exception):
    """Raised when pipeline configuration is invalid."""
    pass

def parse_pipeline_config(yaml_content: str) -> Dict[str, Any]:
    """Parse pipeline YAML configuration from string."""
    try:
        config = yaml.safe_load(yaml_content)
    except yaml.YAMLError as e:
        raise PipelineConfigError(f"Invalid YAML: {e}")
    
    return validate_config(config)

def parse_pipeline_dict(config: Dict[str, Any]) -> Dict[str, Any]:
    """Validate pipeline configuration from dict."""
    return validate_config(config)

def validate_config(config: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Validate pipeline configuration structure."""
    if not config:
        raise PipelineConfigError("Empty pipeline configuration")
    
    if not isinstance(config, dict):
        raise PipelineConfigError("Pipeline configuration must be a dictionary")
    
    # Validate name (optional but recommended)
    name = config.get("name", "Unnamed Pipeline")
    if not isinstance(name, str):
        raise PipelineConfigError("Pipeline 'name' must be a string")
    
    # Validate steps
    if "steps" not in config:
        raise PipelineConfigError("Pipeline must have 'steps' defined")
    
    steps = config["steps"]
    if not isinstance(steps, list):
        raise PipelineConfigError("Pipeline 'steps' must be a list")
    
    if len(steps) == 0:
        raise PipelineConfigError("Pipeline must have at least one step")
    
    validated_steps = []
    for i, step in enumerate(steps):
        validated_step = validate_step(step, i)
        validated_steps.append(validated_step)
    
    return {
        "name": name,
        "steps": validated_steps,
        "env": config.get("env", {}),
    }

def validate_step(step: Dict[str, Any], index: int) -> Dict[str, Any]:
    """Validate a single pipeline step."""
    if not isinstance(step, dict):
        raise PipelineConfigError(f"Step {index} must be a dictionary")
    
    # Required fields
    if "name" not in step:
        raise PipelineConfigError(f"Step {index} missing 'name'")
    
    if "image" not in step:
        raise PipelineConfigError(f"Step {index} missing 'image'")
    
    if "commands" not in step:
        raise PipelineConfigError(f"Step {index} missing 'commands'")
    
    # Validate types
    if not isinstance(step["name"], str):
        raise PipelineConfigError(f"Step {index} 'name' must be a string")
    
    if not isinstance(step["image"], str):
        raise PipelineConfigError(f"Step {index} 'image' must be a string")
    
    if not isinstance(step["commands"], list):
        raise PipelineConfigError(f"Step {index} 'commands' must be a list")
    
    for j, cmd in enumerate(step["commands"]):
        if not isinstance(cmd, str):
            raise PipelineConfigError(f"Step {index} command {j} must be a string")
    
    return {
        "name": step["name"],
        "image": step["image"],
        "commands": step["commands"],
        "env": step.get("env", {}),
        "timeout": step.get("timeout", 600),  # Default 10 min timeout
    }
EOF

echo "✅ api/src/services/pipeline_parser.py"

# ============================================
# Updated Queue Service
# ============================================
cat > api/src/services/queue.py << 'EOF'
"""
Redis queue service for pipeline jobs.
"""

import redis.asyncio as redis
import json
from typing import Dict, Any, Optional
from datetime import datetime

from api.src.config import get_settings

settings = get_settings()

PIPELINE_QUEUE = "pipelinex:jobs"
PIPELINE_STATUS = "pipelinex:status"

async def get_redis_client() -> redis.Redis:
    """Get async Redis client."""
    return redis.from_url(settings.redis_url, decode_responses=True)

async def enqueue_pipeline_run(run_id: str, config: Dict[str, Any], repo_info: Dict[str, Any]):
    """Add pipeline run to processing queue."""
    client = await get_redis_client()
    
    job = {
        "run_id": run_id,
        "config": config,
        "repo_info": repo_info,
        "queued_at": datetime.utcnow().isoformat(),
    }
    
    try:
        await client.lpush(PIPELINE_QUEUE, json.dumps(job))
        await client.hset(PIPELINE_STATUS, run_id, "queued")
    finally:
        await client.close()

async def dequeue_pipeline_run(timeout: int = 5) -> Optional[Dict[str, Any]]:
    """
    Get next pipeline run from queue.
    Blocks for `timeout` seconds if queue is empty.
    """
    client = await get_redis_client()
    
    try:
        result = await client.brpop(PIPELINE_QUEUE, timeout=timeout)
        if result:
            _, job_data = result
            return json.loads(job_data)
        return None
    finally:
        await client.close()

async def update_run_status(run_id: str, status: str):
    """Update pipeline run status in Redis."""
    client = await get_redis_client()
    
    try:
        await client.hset(PIPELINE_STATUS, run_id, status)
    finally:
        await client.close()

async def get_run_status(run_id: str) -> Optional[str]:
    """Get pipeline run status from Redis."""
    client = await get_redis_client()
    
    try:
        return await client.hget(PIPELINE_STATUS, run_id)
    finally:
        await client.close()

async def get_queue_length() -> int:
    """Get number of jobs in queue."""
    client = await get_redis_client()
    
    try:
        return await client.llen(PIPELINE_QUEUE)
    finally:
        await client.close()
EOF

echo "✅ api/src/services/queue.py"

# ============================================
# Updated Services __init__
# ============================================
cat > api/src/services/__init__.py << 'EOF'
from api.src.services.github import (
    verify_signature,
    clone_repository,
    fetch_pipeline_config,
    parse_webhook_payload,
    cleanup_repo,
)
from api.src.services.pipeline_parser import (
    parse_pipeline_config,
    parse_pipeline_dict,
    PipelineConfigError,
)
from api.src.services.queue import (
    enqueue_pipeline_run,
    dequeue_pipeline_run,
    update_run_status,
    get_run_status,
    get_queue_length,
)

__all__ = [
    "verify_signature",
    "clone_repository",
    "fetch_pipeline_config",
    "parse_webhook_payload",
    "cleanup_repo",
    "parse_pipeline_config",
    "parse_pipeline_dict",
    "PipelineConfigError",
    "enqueue_pipeline_run",
    "dequeue_pipeline_run",
    "update_run_status",
    "get_run_status",
    "get_queue_length",
]
EOF

echo "✅ api/src/services/__init__.py"

# ============================================
# Updated Webhooks Route
# ============================================
cat > api/src/routes/webhooks.py << 'EOF'
"""
GitHub webhook endpoints.
"""

from fastapi import APIRouter, Request, HTTPException, Header, Depends, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
import logging

from api.src.db.database import get_db
from api.src.models.pipeline import Repository, PipelineRun, PipelineStep
from api.src.services.github import (
    verify_signature,
    parse_webhook_payload,
    clone_repository,
    fetch_pipeline_config,
    cleanup_repo,
)
from api.src.services.pipeline_parser import parse_pipeline_dict, PipelineConfigError
from api.src.services.queue import enqueue_pipeline_run

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/webhooks", tags=["webhooks"])

async def process_push_event(
    payload: dict,
    db: AsyncSession,
):
    """Process GitHub push event and create pipeline run."""
    
    # Parse webhook payload
    webhook_data = parse_webhook_payload(payload)
    
    if not webhook_data["commit_sha"]:
        logger.warning("No commit SHA in webhook payload")
        return {"status": "skipped", "reason": "No commit SHA"}
    
    # Skip if branch is not main/master (configurable later)
    # if webhook_data["branch"] not in ["main", "master"]:
    #     return {"status": "skipped", "reason": f"Branch {webhook_data['branch']} not configured"}
    
    # Get or create repository
    repo_query = select(Repository).where(
        Repository.full_name == webhook_data["repo_full_name"]
    )
    result = await db.execute(repo_query)
    repository = result.scalar_one_or_none()
    
    if not repository:
        repository = Repository(
            name=webhook_data["repo_name"],
            full_name=webhook_data["repo_full_name"],
            clone_url=webhook_data["clone_url"],
        )
        db.add(repository)
        await db.flush()
    
    # Clone repo and fetch pipeline config
    repo_path = None
    try:
        repo_path = await clone_repository(
            webhook_data["clone_url"],
            webhook_data["commit_sha"]
        )
        
        pipeline_config = await fetch_pipeline_config(repo_path)
        
        if not pipeline_config:
            logger.info(f"No pipeline config found in {webhook_data['repo_full_name']}")
            return {"status": "skipped", "reason": "No pipeline configuration found"}
        
        # Validate config
        validated_config = parse_pipeline_dict(pipeline_config)
        
    except PipelineConfigError as e:
        logger.error(f"Invalid pipeline config: {e}")
        return {"status": "error", "reason": str(e)}
    except Exception as e:
        logger.error(f"Failed to process repository: {e}")
        return {"status": "error", "reason": str(e)}
    finally:
        if repo_path:
            cleanup_repo(repo_path)
    
    # Create pipeline run
    pipeline_run = PipelineRun(
        repository_id=repository.id,
        commit_sha=webhook_data["commit_sha"],
        branch=webhook_data["branch"],
        status="queued",
        triggered_by=webhook_data["pusher"],
        config=validated_config,
    )
    db.add(pipeline_run)
    await db.flush()
    
    # Create pipeline steps
    for i, step_config in enumerate(validated_config["steps"]):
        step = PipelineStep(
            run_id=pipeline_run.id,
            name=step_config["name"],
            image=step_config["image"],
            commands=step_config["commands"],
            status="pending",
            step_order=i,
        )
        db.add(step)
    
    await db.commit()
    
    # Enqueue for processing
    await enqueue_pipeline_run(
        run_id=str(pipeline_run.id),
        config=validated_config,
        repo_info=webhook_data,
    )
    
    logger.info(f"Pipeline run {pipeline_run.id} created and queued")
    
    return {
        "status": "queued",
        "run_id": str(pipeline_run.id),
        "steps": len(validated_config["steps"]),
    }

@router.post("/github")
async def github_webhook(
    request: Request,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    x_hub_signature_256: Optional[str] = Header(None),
    x_github_event: Optional[str] = Header(None),
):
    """
    Receive GitHub webhook events.
    """
    # Get raw body for signature verification
    body = await request.body()
    
    # Verify signature
    if x_hub_signature_256:
        if not verify_signature(body, x_hub_signature_256):
            raise HTTPException(status_code=401, detail="Invalid signature")
    
    # Parse JSON payload
    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON payload")
    
    # Handle different event types
    if x_github_event == "ping":
        return {"status": "pong", "message": "Webhook configured successfully"}
    
    if x_github_event == "push":
        result = await process_push_event(payload, db)
        return result
    
    # Ignore other events
    return {
        "status": "ignored",
        "event": x_github_event,
        "message": f"Event type '{x_github_event}' not handled"
    }

@router.get("/test")
async def test_webhook():
    """Test endpoint to verify webhook route is working."""
    return {"status": "ok", "message": "Webhook endpoint is ready"}
EOF

echo "✅ api/src/routes/webhooks.py"

# ============================================
# Updated Health Route (add queue status)
# ============================================
cat > api/src/routes/health.py << 'EOF'
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
import redis.asyncio as redis

from api.src.db.database import get_db
from api.src.config import get_settings
from api.src.services.queue import get_queue_length

settings = get_settings()

router = APIRouter(tags=["health"])

@router.get("/health")
async def health_check():
    return {"status": "healthy", "service": "pipelinex-api"}

@router.get("/health/db")
async def db_health_check(db: AsyncSession = Depends(get_db)):
    try:
        await db.execute(text("SELECT 1"))
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "database": str(e)}

@router.get("/health/redis")
async def redis_health_check():
    try:
        client = redis.from_url(settings.redis_url)
        await client.ping()
        await client.close()
        return {"status": "healthy", "redis": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "redis": str(e)}

@router.get("/health/queue")
async def queue_health_check():
    try:
        queue_length = await get_queue_length()
        return {
            "status": "healthy",
            "queue_length": queue_length,
        }
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

@router.get("/health/all")
async def full_health_check(db: AsyncSession = Depends(get_db)):
    """Combined health check for all services."""
    health = {
        "api": "healthy",
        "database": "unknown",
        "redis": "unknown",
        "queue_length": 0,
    }
    
    # Check database
    try:
        await db.execute(text("SELECT 1"))
        health["database"] = "healthy"
    except Exception as e:
        health["database"] = f"unhealthy: {e}"
    
    # Check Redis
    try:
        client = redis.from_url(settings.redis_url)
        await client.ping()
        await client.close()
        health["redis"] = "healthy"
    except Exception as e:
        health["redis"] = f"unhealthy: {e}"
    
    # Check queue
    try:
        health["queue_length"] = await get_queue_length()
    except Exception:
        pass
    
    overall = "healthy" if all(
        v == "healthy" for k, v in health.items() 
        if k not in ["queue_length"]
    ) else "degraded"
    
    return {"status": overall, "services": health}
EOF

echo "✅ api/src/routes/health.py"

# ============================================
# Updated Pipelines Route (add manual trigger)
# ============================================
cat > api/src/routes/pipelines.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from typing import List, Optional
from uuid import UUID
from pydantic import BaseModel

from api.src.db.database import get_db
from api.src.models.pipeline import PipelineRun, PipelineStep, Repository
from api.src.models.run import PipelineRunResponse, RepositoryResponse
from api.src.services.queue import get_run_status

router = APIRouter(prefix="/pipelines", tags=["pipelines"])

class ManualTriggerRequest(BaseModel):
    repository_url: str
    branch: str = "main"
    commit_sha: Optional[str] = None

@router.get("/runs", response_model=List[PipelineRunResponse])
async def list_runs(
    limit: int = 20,
    offset: int = 0,
    status: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """List all pipeline runs."""
    query = (
        select(PipelineRun)
        .options(selectinload(PipelineRun.steps))
        .order_by(PipelineRun.created_at.desc())
    )
    
    if status:
        query = query.where(PipelineRun.status == status)
    
    query = query.limit(limit).offset(offset)
    
    result = await db.execute(query)
    runs = result.scalars().all()
    return runs

@router.get("/runs/{run_id}", response_model=PipelineRunResponse)
async def get_run(run_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get a specific pipeline run."""
    query = (
        select(PipelineRun)
        .options(selectinload(PipelineRun.steps))
        .where(PipelineRun.id == run_id)
    )
    result = await db.execute(query)
    run = result.scalar_one_or_none()
    
    if not run:
        raise HTTPException(status_code=404, detail="Pipeline run not found")
    
    return run

@router.get("/runs/{run_id}/status")
async def get_run_status_endpoint(run_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get real-time status of a pipeline run."""
    # Get from database
    query = (
        select(PipelineRun)
        .options(selectinload(PipelineRun.steps))
        .where(PipelineRun.id == run_id)
    )
    result = await db.execute(query)
    run = result.scalar_one_or_none()
    
    if not run:
        raise HTTPException(status_code=404, detail="Pipeline run not found")
    
    # Get live status from Redis
    redis_status = await get_run_status(str(run_id))
    
    return {
        "run_id": str(run_id),
        "db_status": run.status,
        "live_status": redis_status,
        "steps": [
            {
                "name": step.name,
                "status": step.status,
                "order": step.step_order,
            }
            for step in sorted(run.steps, key=lambda s: s.step_order)
        ]
    }

@router.get("/runs/{run_id}/logs")
async def get_run_logs(run_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get logs for all steps in a pipeline run."""
    query = (
        select(PipelineStep)
        .where(PipelineStep.run_id == run_id)
        .order_by(PipelineStep.step_order)
    )
    result = await db.execute(query)
    steps = result.scalars().all()
    
    if not steps:
        raise HTTPException(status_code=404, detail="Pipeline run not found")
    
    return {
        "run_id": str(run_id),
        "steps": [
            {
                "name": step.name,
                "status": step.status,
                "logs": step.logs,
                "started_at": step.started_at,
                "finished_at": step.finished_at,
            }
            for step in steps
        ]
    }

@router.get("/repositories", response_model=List[RepositoryResponse])
async def list_repositories(db: AsyncSession = Depends(get_db)):
    """List all registered repositories."""
    query = select(Repository).order_by(Repository.created_at.desc())
    result = await db.execute(query)
    repos = result.scalars().all()
    return repos

@router.get("/stats")
async def get_pipeline_stats(db: AsyncSession = Depends(get_db)):
    """Get pipeline statistics."""
    from sqlalchemy import func
    
    # Count runs by status
    status_query = (
        select(PipelineRun.status, func.count(PipelineRun.id))
        .group_by(PipelineRun.status)
    )
    result = await db.execute(status_query)
    status_counts = {row[0]: row[1] for row in result.all()}
    
    # Count total repositories
    repo_count_query = select(func.count(Repository.id))
    result = await db.execute(repo_count_query)
    repo_count = result.scalar()
    
    return {
        "repositories": repo_count,
        "runs": status_counts,
        "total_runs": sum(status_counts.values()),
    }
EOF

echo "✅ api/src/routes/pipelines.py"

# ============================================
# Update API Dockerfile to include git
# ============================================
cat > api/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies including git
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for caching
COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY api/ ./api/

# Set Python path
ENV PYTHONPATH=/app

EXPOSE 8000

CMD ["uvicorn", "api.src.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
EOF

echo "✅ api/Dockerfile (added git)"

# ============================================
# Test files
# ============================================
cat > api/tests/test_parser.py << 'EOF'
"""Tests for pipeline parser."""

import pytest
from api.src.services.pipeline_parser import (
    parse_pipeline_config,
    parse_pipeline_dict,
    PipelineConfigError,
)

def test_valid_pipeline():
    config = """
name: Test Pipeline
steps:
  - name: Build
    image: node:18
    commands:
      - npm install
      - npm run build
  - name: Test
    image: node:18
    commands:
      - npm test
"""
    result = parse_pipeline_config(config)
    assert result["name"] == "Test Pipeline"
    assert len(result["steps"]) == 2
    assert result["steps"][0]["name"] == "Build"
    assert result["steps"][1]["image"] == "node:18"

def test_missing_steps():
    config = """
name: Bad Pipeline
"""
    with pytest.raises(PipelineConfigError, match="must have 'steps'"):
        parse_pipeline_config(config)

def test_missing_step_name():
    config = """
name: Bad Pipeline
steps:
  - image: node:18
    commands:
      - npm install
"""
    with pytest.raises(PipelineConfigError, match="missing 'name'"):
        parse_pipeline_config(config)

def test_missing_step_image():
    config = """
name: Bad Pipeline
steps:
  - name: Build
    commands:
      - npm install
"""
    with pytest.raises(PipelineConfigError, match="missing 'image'"):
        parse_pipeline_config(config)

def test_empty_config():
    with pytest.raises(PipelineConfigError, match="Empty"):
        parse_pipeline_config("")

def test_dict_parsing():
    config = {
        "name": "Dict Pipeline",
        "steps": [
            {"name": "Step 1", "image": "alpine", "commands": ["echo hello"]}
        ]
    }
    result = parse_pipeline_dict(config)
    assert result["name"] == "Dict Pipeline"
    assert len(result["steps"]) == 1
EOF

echo "✅ api/tests/test_parser.py"

cat > api/tests/test_webhooks.py << 'EOF'
"""Tests for webhook handling."""

import pytest
from api.src.services.github import parse_webhook_payload, verify_signature

def test_parse_push_payload():
    payload = {
        "ref": "refs/heads/main",
        "repository": {
            "name": "test-repo",
            "full_name": "user/test-repo",
            "clone_url": "https://github.com/user/test-repo.git",
        },
        "head_commit": {
            "id": "abc123def456",
            "message": "Test commit",
        },
        "pusher": {
            "name": "testuser",
        },
    }
    
    result = parse_webhook_payload(payload)
    
    assert result["repo_name"] == "test-repo"
    assert result["repo_full_name"] == "user/test-repo"
    assert result["branch"] == "main"
    assert result["commit_sha"] == "abc123def456"
    assert result["pusher"] == "testuser"

def test_parse_payload_with_after():
    """Test fallback to 'after' field for commit SHA."""
    payload = {
        "ref": "refs/heads/feature",
        "after": "xyz789",
        "repository": {
            "name": "repo",
            "full_name": "user/repo",
            "clone_url": "https://github.com/user/repo.git",
        },
        "head_commit": {},
        "pusher": {"name": "user"},
    }
    
    result = parse_webhook_payload(payload)
    assert result["commit_sha"] == "xyz789"
    assert result["branch"] == "feature"

def test_verify_signature_without_secret():
    """When no secret is configured, verification should pass."""
    # This test assumes GITHUB_WEBHOOK_SECRET is not set
    result = verify_signature(b"payload", "sha256=anything")
    assert result is True
EOF

echo "✅ api/tests/test_webhooks.py"

# ============================================
# Update requirements.txt with test deps
# ============================================
cat > api/requirements.txt << 'EOF'
fastapi==0.109.0
uvicorn[standard]==0.27.0
sqlalchemy==2.0.25
asyncpg==0.29.0
psycopg2-binary==2.9.9
pydantic==2.5.3
pydantic-settings==2.1.0
redis==5.0.1
httpx==0.26.0
PyYAML==6.0.1
python-dotenv==1.0.0
pytest==7.4.4
pytest-asyncio==0.23.3
EOF

echo "✅ api/requirements.txt (added test deps)"

echo ""
echo "============================================"
echo "🎉 Phase 2 setup complete!"
echo "============================================"
echo ""
echo "New features:"
echo "  - GitHub webhook processing"
echo "  - Pipeline YAML parsing & validation"
echo "  - Redis job queue"
echo "  - Repository cloning"
echo ""
echo "New endpoints:"
echo "  - POST /api/webhooks/github - receive webhooks"
echo "  - GET  /api/webhooks/test   - test endpoint"
echo "  - GET  /health/redis        - Redis health"
echo "  - GET  /health/queue        - queue status"
echo "  - GET  /health/all          - full health check"
echo "  - GET  /api/pipelines/stats - pipeline statistics"
echo ""
echo "Next steps:"
echo "  1. Rebuild: docker-compose down && docker-compose up --build"
echo "  2. Test: http://localhost:8000/health/all"
echo "  3. View docs: http://localhost:8000/docs"
echo ""
