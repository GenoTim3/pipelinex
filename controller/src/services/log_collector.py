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
