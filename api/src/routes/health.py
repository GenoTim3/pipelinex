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
