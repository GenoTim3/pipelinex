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
