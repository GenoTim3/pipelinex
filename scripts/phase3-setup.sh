#!/bin/bash

# PipelineX Phase 3 Setup Script
# Controller + Kubernetes Implementation
# Run from the pipelinex root directory

set -e

echo "🚀 Setting up Phase 3: Controller + Kubernetes"

# ============================================
# Controller Requirements
# ============================================
cat > controller/requirements.txt << 'EOF'
kubernetes==29.0.0
redis==5.0.1
sqlalchemy==2.0.25
asyncpg==0.29.0
psycopg2-binary==2.9.9
pydantic==2.5.3
pydantic-settings==2.1.0
httpx==0.26.0
python-dotenv==1.0.0
EOF

echo "✅ controller/requirements.txt"

# ============================================
# Controller Config
# ============================================
cat > controller/src/config.py << 'EOF'
from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    database_url: str = "postgresql://pipelinex:pipelinex@localhost:5432/pipelinex"
    redis_url: str = "redis://localhost:6379/0"
    
    # Kubernetes settings
    k8s_namespace: str = "pipelinex"
    k8s_in_cluster: bool = False  # Set True when running inside K8s
    
    # Job settings
    job_timeout: int = 600  # 10 minutes default
    job_ttl_after_finished: int = 300  # Clean up jobs after 5 min
    
    class Config:
        env_file = ".env"

@lru_cache()
def get_settings() -> Settings:
    return Settings()
EOF

echo "✅ controller/src/config.py"

# ============================================
# Kubernetes Client
# ============================================
cat > controller/src/k8s/client.py << 'EOF'
"""
Kubernetes client initialization and utilities.
"""

from kubernetes import client, config
from kubernetes.client.rest import ApiException
import logging

from controller.src.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

_api_client = None
_batch_v1 = None
_core_v1 = None

def init_k8s_client():
    """Initialize Kubernetes client."""
    global _api_client, _batch_v1, _core_v1
    
    try:
        if settings.k8s_in_cluster:
            # Running inside Kubernetes
            config.load_incluster_config()
            logger.info("Loaded in-cluster Kubernetes config")
        else:
            # Running locally (Docker Desktop, minikube, etc.)
            config.load_kube_config()
            logger.info("Loaded local Kubernetes config")
        
        _api_client = client.ApiClient()
        _batch_v1 = client.BatchV1Api(_api_client)
        _core_v1 = client.CoreV1Api(_api_client)
        
        # Test connection
        _core_v1.list_namespace(limit=1)
        logger.info("Kubernetes client initialized successfully")
        
        return True
    except Exception as e:
        logger.error(f"Failed to initialize Kubernetes client: {e}")
        return False

def get_batch_api() -> client.BatchV1Api:
    """Get BatchV1 API client for Job operations."""
    global _batch_v1
    if _batch_v1 is None:
        init_k8s_client()
    return _batch_v1

def get_core_api() -> client.CoreV1Api:
    """Get CoreV1 API client for Pod operations."""
    global _core_v1
    if _core_v1 is None:
        init_k8s_client()
    return _core_v1

def ensure_namespace():
    """Ensure the pipelinex namespace exists."""
    core_v1 = get_core_api()
    
    try:
        core_v1.read_namespace(name=settings.k8s_namespace)
        logger.info(f"Namespace '{settings.k8s_namespace}' exists")
    except ApiException as e:
        if e.status == 404:
            # Create namespace
            namespace = client.V1Namespace(
                metadata=client.V1ObjectMeta(name=settings.k8s_namespace)
            )
            core_v1.create_namespace(body=namespace)
            logger.info(f"Created namespace '{settings.k8s_namespace}'")
        else:
            raise

def get_pod_logs(pod_name: str, namespace: str = None) -> str:
    """Get logs from a pod."""
    namespace = namespace or settings.k8s_namespace
    core_v1 = get_core_api()
    
    try:
        logs = core_v1.read_namespaced_pod_log(
            name=pod_name,
            namespace=namespace,
        )
        return logs
    except ApiException as e:
        logger.error(f"Failed to get logs for pod {pod_name}: {e}")
        return f"Error fetching logs: {e.reason}"

def delete_job(job_name: str, namespace: str = None):
    """Delete a job and its pods."""
    namespace = namespace or settings.k8s_namespace
    batch_v1 = get_batch_api()
    
    try:
        batch_v1.delete_namespaced_job(
            name=job_name,
            namespace=namespace,
            body=client.V1DeleteOptions(
                propagation_policy="Foreground"
            )
        )
        logger.info(f"Deleted job {job_name}")
    except ApiException as e:
        if e.status != 404:
            logger.error(f"Failed to delete job {job_name}: {e}")
EOF

echo "✅ controller/src/k8s/client.py"

# ============================================
# Job Builder
# ============================================
cat > controller/src/k8s/job_builder.py << 'EOF'
"""
Kubernetes Job builder for pipeline steps.
"""

from kubernetes import client
from typing import List, Dict, Any, Optional
import hashlib

from controller.src.config import get_settings

settings = get_settings()

def build_job_name(run_id: str, step_order: int, step_name: str) -> str:
    """Generate a unique job name."""
    # K8s names must be lowercase, alphanumeric, max 63 chars
    safe_name = step_name.lower().replace(" ", "-").replace("_", "-")
    safe_name = "".join(c for c in safe_name if c.isalnum() or c == "-")
    safe_name = safe_name[:20]  # Truncate step name
    
    # Use short hash of run_id for uniqueness
    run_hash = hashlib.md5(run_id.encode()).hexdigest()[:8]
    
    return f"px-{run_hash}-{step_order}-{safe_name}"

def build_job(
    run_id: str,
    step_order: int,
    step_name: str,
    image: str,
    commands: List[str],
    env_vars: Optional[Dict[str, str]] = None,
    timeout: int = 600,
) -> client.V1Job:
    """
    Build a Kubernetes Job for a pipeline step.
    """
    job_name = build_job_name(run_id, step_order, step_name)
    
    # Build environment variables
    env = [
        client.V1EnvVar(name="PIPELINEX_RUN_ID", value=run_id),
        client.V1EnvVar(name="PIPELINEX_STEP_ORDER", value=str(step_order)),
        client.V1EnvVar(name="PIPELINEX_STEP_NAME", value=step_name),
    ]
    
    if env_vars:
        for key, value in env_vars.items():
            env.append(client.V1EnvVar(name=key, value=value))
    
    # Build the shell command that runs all commands in sequence
    # Join commands with && so it fails fast on error
    shell_command = " && ".join(commands)
    
    # Container spec
    container = client.V1Container(
        name="step",
        image=image,
        command=["/bin/sh", "-c"],
        args=[shell_command],
        env=env,
        resources=client.V1ResourceRequirements(
            requests={"cpu": "100m", "memory": "128Mi"},
            limits={"cpu": "500m", "memory": "512Mi"},
        ),
    )
    
    # Pod spec
    pod_spec = client.V1PodSpec(
        containers=[container],
        restart_policy="Never",
    )
    
    # Pod template
    template = client.V1PodTemplateSpec(
        metadata=client.V1ObjectMeta(
            labels={
                "app": "pipelinex",
                "run-id": run_id,
                "step-order": str(step_order),
            }
        ),
        spec=pod_spec,
    )
    
    # Job spec
    job_spec = client.V1JobSpec(
        template=template,
        backoff_limit=0,  # Don't retry failed jobs
        active_deadline_seconds=timeout,
        ttl_seconds_after_finished=settings.job_ttl_after_finished,
    )
    
    # Job object
    job = client.V1Job(
        api_version="batch/v1",
        kind="Job",
        metadata=client.V1ObjectMeta(
            name=job_name,
            namespace=settings.k8s_namespace,
            labels={
                "app": "pipelinex",
                "run-id": run_id,
                "step-order": str(step_order),
            },
        ),
        spec=job_spec,
    )
    
    return job

def get_job_status(job: client.V1Job) -> str:
    """
    Determine job status from Kubernetes Job object.
    Returns: 'pending', 'running', 'succeeded', 'failed'
    """
    if job.status is None:
        return "pending"
    
    if job.status.succeeded and job.status.succeeded > 0:
        return "succeeded"
    
    if job.status.failed and job.status.failed > 0:
        return "failed"
    
    if job.status.active and job.status.active > 0:
        return "running"
    
    return "pending"
EOF

echo "✅ controller/src/k8s/job_builder.py"

# ============================================
# K8s __init__
# ============================================
cat > controller/src/k8s/__init__.py << 'EOF'
from controller.src.k8s.client import (
    init_k8s_client,
    get_batch_api,
    get_core_api,
    ensure_namespace,
    get_pod_logs,
    delete_job,
)
from controller.src.k8s.job_builder import (
    build_job,
    build_job_name,
    get_job_status,
)

__all__ = [
    "init_k8s_client",
    "get_batch_api",
    "get_core_api",
    "ensure_namespace",
    "get_pod_logs",
    "delete_job",
    "build_job",
    "build_job_name",
    "get_job_status",
]
EOF

echo "✅ controller/src/k8s/__init__.py"

# ============================================
# Step Model
# ============================================
cat > controller/src/models/step.py << 'EOF'
"""
Step execution models.
"""

from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from datetime import datetime
from enum import Enum

class StepStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    CANCELLED = "cancelled"

class StepConfig(BaseModel):
    name: str
    image: str
    commands: List[str]
    env: Dict[str, str] = {}
    timeout: int = 600

class StepResult(BaseModel):
    step_order: int
    name: str
    status: StepStatus
    logs: Optional[str] = None
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    error: Optional[str] = None

class PipelineJob(BaseModel):
    run_id: str
    config: Dict[str, Any]
    repo_info: Dict[str, Any]
    queued_at: str
EOF

echo "✅ controller/src/models/step.py"

# ============================================
# Models __init__
# ============================================
cat > controller/src/models/__init__.py << 'EOF'
from controller.src.models.step import (
    StepStatus,
    StepConfig,
    StepResult,
    PipelineJob,
)

__all__ = [
    "StepStatus",
    "StepConfig",
    "StepResult",
    "PipelineJob",
]
EOF

echo "✅ controller/src/models/__init__.py"

# ============================================
# Log Collector
# ============================================
cat > controller/src/services/log_collector.py << 'EOF'
"""
Collect logs from Kubernetes pods.
"""

import logging
from typing import Optional
from kubernetes.client.rest import ApiException

from controller.src.k8s.client import get_core_api, get_batch_api
from controller.src.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

async def get_job_pod_name(job_name: str) -> Optional[str]:
    """Get the pod name for a job."""
    core_v1 = get_core_api()
    
    try:
        pods = core_v1.list_namespaced_pod(
            namespace=settings.k8s_namespace,
            label_selector=f"job-name={job_name}",
        )
        
        if pods.items:
            return pods.items[0].metadata.name
        return None
    except ApiException as e:
        logger.error(f"Failed to get pod for job {job_name}: {e}")
        return None

async def collect_logs(job_name: str) -> str:
    """Collect logs from a job's pod."""
    core_v1 = get_core_api()
    
    pod_name = await get_job_pod_name(job_name)
    if not pod_name:
        return "No pod found for job"
    
    try:
        logs = core_v1.read_namespaced_pod_log(
            name=pod_name,
            namespace=settings.k8s_namespace,
            tail_lines=1000,  # Limit log lines
        )
        return logs
    except ApiException as e:
        if e.status == 400:
            # Pod might not have started yet
            return "Waiting for pod to start..."
        logger.error(f"Failed to collect logs for {pod_name}: {e}")
        return f"Error collecting logs: {e.reason}"

async def stream_logs(job_name: str):
    """
    Stream logs from a job's pod.
    Yields log lines as they come in.
    """
    core_v1 = get_core_api()
    
    pod_name = await get_job_pod_name(job_name)
    if not pod_name:
        yield "Waiting for pod..."
        return
    
    try:
        # Use watch to stream logs
        for line in core_v1.read_namespaced_pod_log(
            name=pod_name,
            namespace=settings.k8s_namespace,
            follow=True,
            _preload_content=False,
        ).stream():
            yield line.decode("utf-8")
    except ApiException as e:
        yield f"Error streaming logs: {e.reason}"
EOF

echo "✅ controller/src/services/log_collector.py"

# ============================================
# Status Reporter
# ============================================
cat > controller/src/services/status_reporter.py << 'EOF'
"""
Report pipeline and step status to database.
"""

import logging
from datetime import datetime
from typing import Optional
from sqlalchemy import create_engine, update
from sqlalchemy.orm import sessionmaker

from controller.src.config import get_settings
from controller.src.models.step import StepStatus

logger = logging.getLogger(__name__)
settings = get_settings()

# Sync database connection for controller
engine = create_engine(settings.database_url)
SessionLocal = sessionmaker(bind=engine)

def update_run_status(
    run_id: str,
    status: str,
    started_at: Optional[datetime] = None,
    finished_at: Optional[datetime] = None,
):
    """Update pipeline run status in database."""
    from controller.src.models.db import PipelineRun
    
    with SessionLocal() as session:
        values = {"status": status, "updated_at": datetime.utcnow()}
        
        if started_at:
            values["started_at"] = started_at
        if finished_at:
            values["finished_at"] = finished_at
        
        session.execute(
            update(PipelineRun)
            .where(PipelineRun.id == run_id)
            .values(**values)
        )
        session.commit()
        logger.info(f"Updated run {run_id} status to {status}")

def update_step_status(
    run_id: str,
    step_order: int,
    status: str,
    logs: Optional[str] = None,
    started_at: Optional[datetime] = None,
    finished_at: Optional[datetime] = None,
):
    """Update pipeline step status in database."""
    from controller.src.models.db import PipelineStep
    
    with SessionLocal() as session:
        values = {"status": status, "updated_at": datetime.utcnow()}
        
        if logs is not None:
            values["logs"] = logs
        if started_at:
            values["started_at"] = started_at
        if finished_at:
            values["finished_at"] = finished_at
        
        session.execute(
            update(PipelineStep)
            .where(PipelineStep.run_id == run_id)
            .where(PipelineStep.step_order == step_order)
            .values(**values)
        )
        session.commit()
        logger.debug(f"Updated step {step_order} of run {run_id} to {status}")

def get_run_steps(run_id: str):
    """Get all steps for a run."""
    from controller.src.models.db import PipelineStep
    
    with SessionLocal() as session:
        steps = session.query(PipelineStep).filter(
            PipelineStep.run_id == run_id
        ).order_by(PipelineStep.step_order).all()
        
        return [
            {
                "order": s.step_order,
                "name": s.name,
                "image": s.image,
                "commands": s.commands,
                "status": s.status,
            }
            for s in steps
        ]
EOF

echo "✅ controller/src/services/status_reporter.py"

# ============================================
# Database Models for Controller
# ============================================
cat > controller/src/models/db.py << 'EOF'
"""
Database models for controller (sync version).
"""

from sqlalchemy import Column, String, DateTime, ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import declarative_base
from sqlalchemy.sql import func
import uuid

Base = declarative_base()

class PipelineRun(Base):
    __tablename__ = "pipeline_runs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    repository_id = Column(UUID(as_uuid=True))
    commit_sha = Column(String(40), nullable=False)
    branch = Column(String(255), nullable=False)
    status = Column(String(50), default="pending")
    triggered_by = Column(String(255))
    config = Column(JSONB)
    started_at = Column(DateTime)
    finished_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

class PipelineStep(Base):
    __tablename__ = "pipeline_steps"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    run_id = Column(UUID(as_uuid=True), ForeignKey("pipeline_runs.id"))
    name = Column(String(255), nullable=False)
    image = Column(String(255), nullable=False)
    commands = Column(JSONB, nullable=False)
    status = Column(String(50), default="pending")
    step_order = Column(Integer, nullable=False)
    logs = Column(Text)
    started_at = Column(DateTime)
    finished_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
EOF

echo "✅ controller/src/models/db.py"

# ============================================
# Executor
# ============================================
cat > controller/src/services/executor.py << 'EOF'
"""
Pipeline executor - runs pipeline steps on Kubernetes.
"""

import logging
import time
from datetime import datetime
from typing import Dict, Any
from kubernetes.client.rest import ApiException

from controller.src.config import get_settings
from controller.src.k8s import (
    get_batch_api,
    ensure_namespace,
    build_job,
    build_job_name,
    get_job_status,
)
from controller.src.services.log_collector import collect_logs
from controller.src.services.status_reporter import (
    update_run_status,
    update_step_status,
)

logger = logging.getLogger(__name__)
settings = get_settings()

async def execute_pipeline(job_data: Dict[str, Any]) -> bool:
    """
    Execute a pipeline run.
    Returns True if all steps succeeded, False otherwise.
    """
    run_id = job_data["run_id"]
    config = job_data["config"]
    steps = config.get("steps", [])
    
    logger.info(f"Starting pipeline run {run_id} with {len(steps)} steps")
    
    # Ensure namespace exists
    ensure_namespace()
    
    # Update run status to running
    update_run_status(run_id, "running", started_at=datetime.utcnow())
    
    all_succeeded = True
    
    for i, step_config in enumerate(steps):
        step_name = step_config["name"]
        logger.info(f"Executing step {i}: {step_name}")
        
        # Update step status
        update_step_status(run_id, i, "running", started_at=datetime.utcnow())
        
        try:
            success = await execute_step(
                run_id=run_id,
                step_order=i,
                step_config=step_config,
            )
            
            if success:
                update_step_status(
                    run_id, i, "succeeded",
                    finished_at=datetime.utcnow()
                )
                logger.info(f"Step {i} ({step_name}) succeeded")
            else:
                update_step_status(
                    run_id, i, "failed",
                    finished_at=datetime.utcnow()
                )
                logger.error(f"Step {i} ({step_name}) failed")
                all_succeeded = False
                break  # Stop on first failure
                
        except Exception as e:
            logger.exception(f"Step {i} ({step_name}) failed with exception")
            update_step_status(
                run_id, i, "failed",
                logs=str(e),
                finished_at=datetime.utcnow()
            )
            all_succeeded = False
            break
    
    # Update final run status
    final_status = "succeeded" if all_succeeded else "failed"
    update_run_status(run_id, final_status, finished_at=datetime.utcnow())
    
    logger.info(f"Pipeline run {run_id} finished with status: {final_status}")
    return all_succeeded

async def execute_step(
    run_id: str,
    step_order: int,
    step_config: Dict[str, Any],
) -> bool:
    """
    Execute a single pipeline step.
    Returns True if succeeded, False if failed.
    """
    batch_v1 = get_batch_api()
    
    # Build the job
    job = build_job(
        run_id=run_id,
        step_order=step_order,
        step_name=step_config["name"],
        image=step_config["image"],
        commands=step_config["commands"],
        env_vars=step_config.get("env"),
        timeout=step_config.get("timeout", settings.job_timeout),
    )
    
    job_name = job.metadata.name
    logger.info(f"Creating job {job_name}")
    
    try:
        # Create the job
        batch_v1.create_namespaced_job(
            namespace=settings.k8s_namespace,
            body=job,
        )
    except ApiException as e:
        if e.status == 409:
            # Job already exists, delete and recreate
            logger.warning(f"Job {job_name} already exists, deleting...")
            batch_v1.delete_namespaced_job(
                name=job_name,
                namespace=settings.k8s_namespace,
                body={}
            )
            time.sleep(2)
            batch_v1.create_namespaced_job(
                namespace=settings.k8s_namespace,
                body=job,
            )
        else:
            raise
    
    # Wait for job to complete
    success = await wait_for_job(job_name, step_config.get("timeout", settings.job_timeout))
    
    # Collect logs
    logs = await collect_logs(job_name)
    update_step_status(run_id, step_order, "running", logs=logs)
    
    return success

async def wait_for_job(job_name: str, timeout: int) -> bool:
    """
    Wait for a job to complete.
    Returns True if succeeded, False if failed or timed out.
    """
    batch_v1 = get_batch_api()
    start_time = time.time()
    
    while True:
        elapsed = time.time() - start_time
        if elapsed > timeout:
            logger.error(f"Job {job_name} timed out after {timeout}s")
            return False
        
        try:
            job = batch_v1.read_namespaced_job(
                name=job_name,
                namespace=settings.k8s_namespace,
            )
            
            status = get_job_status(job)
            
            if status == "succeeded":
                return True
            elif status == "failed":
                return False
            
            # Still running or pending
            time.sleep(2)
            
        except ApiException as e:
            logger.error(f"Error checking job status: {e}")
            time.sleep(5)
EOF

echo "✅ controller/src/services/executor.py"

# ============================================
# Services __init__
# ============================================
cat > controller/src/services/__init__.py << 'EOF'
from controller.src.services.executor import execute_pipeline, execute_step
from controller.src.services.log_collector import collect_logs, stream_logs
from controller.src.services.status_reporter import (
    update_run_status,
    update_step_status,
    get_run_steps,
)

__all__ = [
    "execute_pipeline",
    "execute_step",
    "collect_logs",
    "stream_logs",
    "update_run_status",
    "update_step_status",
    "get_run_steps",
]
EOF

echo "✅ controller/src/services/__init__.py"

# ============================================
# Worker
# ============================================
cat > controller/src/worker.py << 'EOF'
"""
Queue worker - pulls jobs from Redis and executes them.
"""

import asyncio
import logging
import redis
import json
from typing import Optional, Dict, Any

from controller.src.config import get_settings
from controller.src.services.executor import execute_pipeline

logger = logging.getLogger(__name__)
settings = get_settings()

PIPELINE_QUEUE = "pipelinex:jobs"

async def get_next_job() -> Optional[Dict[str, Any]]:
    """Pull next job from Redis queue."""
    client = redis.from_url(settings.redis_url, decode_responses=True)
    
    try:
        result = client.brpop(PIPELINE_QUEUE, timeout=5)
        if result:
            _, job_data = result
            return json.loads(job_data)
        return None
    finally:
        client.close()

async def worker_loop():
    """Main worker loop."""
    logger.info("Worker started, waiting for jobs...")
    
    while True:
        try:
            job = await get_next_job()
            
            if job:
                run_id = job.get("run_id", "unknown")
                logger.info(f"Received job for run {run_id}")
                
                try:
                    await execute_pipeline(job)
                except Exception as e:
                    logger.exception(f"Failed to execute pipeline {run_id}: {e}")
            
        except KeyboardInterrupt:
            logger.info("Worker shutting down...")
            break
        except Exception as e:
            logger.exception(f"Worker error: {e}")
            await asyncio.sleep(5)

def run_worker():
    """Entry point for worker."""
    asyncio.run(worker_loop())
EOF

echo "✅ controller/src/worker.py"

# ============================================
# Controller Main
# ============================================
cat > controller/src/main.py << 'EOF'
"""
PipelineX Controller - Main entry point.
"""

import logging
import sys

from controller.src.config import get_settings
from controller.src.k8s.client import init_k8s_client, ensure_namespace
from controller.src.worker import run_worker

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)

logger = logging.getLogger(__name__)

def main():
    """Main entry point."""
    settings = get_settings()
    
    logger.info("Starting PipelineX Controller")
    logger.info(f"Kubernetes namespace: {settings.k8s_namespace}")
    logger.info(f"Redis URL: {settings.redis_url}")
    
    # Initialize Kubernetes client
    if not init_k8s_client():
        logger.error("Failed to initialize Kubernetes client")
        sys.exit(1)
    
    # Ensure namespace exists
    try:
        ensure_namespace()
    except Exception as e:
        logger.error(f"Failed to ensure namespace: {e}")
        sys.exit(1)
    
    # Start worker
    logger.info("Starting worker...")
    run_worker()

if __name__ == "__main__":
    main()
EOF

echo "✅ controller/src/main.py"

# ============================================
# Controller __init__
# ============================================
cat > controller/src/__init__.py << 'EOF'
EOF

echo "✅ controller/src/__init__.py"

# ============================================
# Controller Dockerfile
# ============================================
cat > controller/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for caching
COPY controller/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY controller/ ./controller/

# Set Python path
ENV PYTHONPATH=/app

CMD ["python", "-m", "controller.src.main"]
EOF

echo "✅ controller/Dockerfile"

# ============================================
# Update docker-compose.yml
# ============================================
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  api:
    build:
      context: .
      dockerfile: api/Dockerfile
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://pipelinex:pipelinex@postgres:5432/pipelinex
      - REDIS_URL=redis://redis:6379/0
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
    volumes:
      - ./api:/app/api
    networks:
      - pipelinex

  controller:
    build:
      context: .
      dockerfile: controller/Dockerfile
    environment:
      - DATABASE_URL=postgresql://pipelinex:pipelinex@postgres:5432/pipelinex
      - REDIS_URL=redis://redis:6379/0
      - K8S_NAMESPACE=pipelinex
      - K8S_IN_CLUSTER=false
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
    volumes:
      - ./controller:/app/controller
      - ~/.kube:/root/.kube:ro  # Mount local kubeconfig
    networks:
      - pipelinex

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: pipelinex
      POSTGRES_PASSWORD: pipelinex
      POSTGRES_DB: pipelinex
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./db/migrations:/docker-entrypoint-initdb.d/migrations
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U pipelinex"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - pipelinex

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - pipelinex

volumes:
  postgres_data:
  redis_data:

networks:
  pipelinex:
    driver: bridge
EOF

echo "✅ docker-compose.yml (added controller)"

# ============================================
# Kubernetes namespace manifest
# ============================================
cat > k8s/manifests/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: pipelinex
  labels:
    app: pipelinex
EOF

echo "✅ k8s/manifests/namespace.yaml"

# ============================================
# Create namespace in K8s
# ============================================
echo ""
echo "Creating Kubernetes namespace..."
kubectl apply -f k8s/manifests/namespace.yaml 2>/dev/null || echo "⚠️  Could not create namespace (kubectl may not be available)"

echo ""
echo "============================================"
echo "🎉 Phase 3 setup complete!"
echo "============================================"
echo ""
echo "Components added:"
echo "  - Kubernetes client & job builder"
echo "  - Pipeline executor"
echo "  - Log collector"
echo "  - Status reporter"
echo "  - Worker queue consumer"
echo ""
echo "Next steps:"
echo "  1. Rebuild: docker-compose down && docker-compose up --build"
echo "  2. Controller will connect to Docker Desktop K8s"
echo "  3. Test by triggering a webhook"
echo ""
