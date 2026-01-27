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
