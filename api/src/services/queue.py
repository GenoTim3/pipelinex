"""
Redis queue service for pipeline jobs.
Implementation in Phase 2.
"""

import redis.asyncio as redis
import json
from typing import Dict, Any

from api.src.config import get_settings

settings = get_settings()

async def get_redis_client():
    """Get async Redis client."""
    return redis.from_url(settings.redis_url)

async def enqueue_pipeline_run(run_id: str, config: Dict[str, Any]):
    """Add pipeline run to processing queue."""
    client = await get_redis_client()
    job = {"run_id": run_id, "config": config}
    await client.lpush("pipeline_jobs", json.dumps(job))
    await client.close()

async def dequeue_pipeline_run() -> Dict[str, Any] | None:
    """Get next pipeline run from queue."""
    client = await get_redis_client()
    result = await client.brpop("pipeline_jobs", timeout=5)
    await client.close()
    if result:
        return json.loads(result[1])
    return None
