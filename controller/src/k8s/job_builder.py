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
