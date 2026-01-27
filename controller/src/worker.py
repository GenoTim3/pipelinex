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
