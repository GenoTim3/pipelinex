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
