from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from typing import List, Optional
from uuid import UUID
from pydantic import BaseModel

from api.src.db.database import get_db
from api.src.models.pipeline import PipelineRun, PipelineStep, Repository
from api.src.models.run import PipelineRunResponse, RepositoryResponse
from api.src.services.queue import get_run_status

router = APIRouter(prefix="/pipelines", tags=["pipelines"])

class ManualTriggerRequest(BaseModel):
    repository_url: str
    branch: str = "main"
    commit_sha: Optional[str] = None

@router.get("/runs", response_model=List[PipelineRunResponse])
async def list_runs(
    limit: int = 20,
    offset: int = 0,
    status: Optional[str] = None,
    db: AsyncSession = Depends(get_db)
):
    """List all pipeline runs."""
    query = (
        select(PipelineRun)
        .options(selectinload(PipelineRun.steps))
        .order_by(PipelineRun.created_at.desc())
    )
    
    if status:
        query = query.where(PipelineRun.status == status)
    
    query = query.limit(limit).offset(offset)
    
    result = await db.execute(query)
    runs = result.scalars().all()
    return runs

@router.get("/runs/{run_id}", response_model=PipelineRunResponse)
async def get_run(run_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get a specific pipeline run."""
    query = (
        select(PipelineRun)
        .options(selectinload(PipelineRun.steps))
        .where(PipelineRun.id == run_id)
    )
    result = await db.execute(query)
    run = result.scalar_one_or_none()
    
    if not run:
        raise HTTPException(status_code=404, detail="Pipeline run not found")
    
    return run

@router.get("/runs/{run_id}/status")
async def get_run_status_endpoint(run_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get real-time status of a pipeline run."""
    # Get from database
    query = (
        select(PipelineRun)
        .options(selectinload(PipelineRun.steps))
        .where(PipelineRun.id == run_id)
    )
    result = await db.execute(query)
    run = result.scalar_one_or_none()
    
    if not run:
        raise HTTPException(status_code=404, detail="Pipeline run not found")
    
    # Get live status from Redis
    redis_status = await get_run_status(str(run_id))
    
    return {
        "run_id": str(run_id),
        "db_status": run.status,
        "live_status": redis_status,
        "steps": [
            {
                "name": step.name,
                "status": step.status,
                "order": step.step_order,
            }
            for step in sorted(run.steps, key=lambda s: s.step_order)
        ]
    }

@router.get("/runs/{run_id}/logs")
async def get_run_logs(run_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get logs for all steps in a pipeline run."""
    query = (
        select(PipelineStep)
        .where(PipelineStep.run_id == run_id)
        .order_by(PipelineStep.step_order)
    )
    result = await db.execute(query)
    steps = result.scalars().all()
    
    if not steps:
        raise HTTPException(status_code=404, detail="Pipeline run not found")
    
    return {
        "run_id": str(run_id),
        "steps": [
            {
                "name": step.name,
                "status": step.status,
                "logs": step.logs,
                "started_at": step.started_at,
                "finished_at": step.finished_at,
            }
            for step in steps
        ]
    }

@router.get("/repositories", response_model=List[RepositoryResponse])
async def list_repositories(db: AsyncSession = Depends(get_db)):
    """List all registered repositories."""
    query = select(Repository).order_by(Repository.created_at.desc())
    result = await db.execute(query)
    repos = result.scalars().all()
    return repos

@router.get("/stats")
async def get_pipeline_stats(db: AsyncSession = Depends(get_db)):
    """Get pipeline statistics."""
    from sqlalchemy import func
    
    # Count runs by status
    status_query = (
        select(PipelineRun.status, func.count(PipelineRun.id))
        .group_by(PipelineRun.status)
    )
    result = await db.execute(status_query)
    status_counts = {row[0]: row[1] for row in result.all()}
    
    # Count total repositories
    repo_count_query = select(func.count(Repository.id))
    result = await db.execute(repo_count_query)
    repo_count = result.scalar()
    
    return {
        "repositories": repo_count,
        "runs": status_counts,
        "total_runs": sum(status_counts.values()),
    }
