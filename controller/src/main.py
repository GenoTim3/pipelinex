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
