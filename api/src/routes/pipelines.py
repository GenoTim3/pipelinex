from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from typing import List
from uuid import UUID

from api.src.db.database import get_db
from api.src.models.pipeline import PipelineRun, Repository
from api.src.models.run import PipelineRunResponse, RepositoryResponse

router = APIRouter(prefix="/pipelines", tags=["pipelines"])

@router.get("/runs", response_model=List[PipelineRunResponse])
async def list_runs(limit: int = 20, offset: int = 0, db: AsyncSession = Depends(get_db)):
    query = (
        select(PipelineRun)
        .options(selectinload(PipelineRun.steps))
        .order_by(PipelineRun.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    result = await db.execute(query)
    runs = result.scalars().all()
    return runs

@router.get("/runs/{run_id}", response_model=PipelineRunResponse)
async def get_run(run_id: UUID, db: AsyncSession = Depends(get_db)):
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

@router.get("/repositories", response_model=List[RepositoryResponse])
async def list_repositories(db: AsyncSession = Depends(get_db)):
    query = select(Repository).order_by(Repository.created_at.desc())
    result = await db.execute(query)
    repos = result.scalars().all()
    return repos
