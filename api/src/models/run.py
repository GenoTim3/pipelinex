from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from uuid import UUID

class StepBase(BaseModel):
    name: str
    image: str
    commands: List[str]

class StepResponse(StepBase):
    id: UUID
    status: str
    step_order: int
    logs: Optional[str] = None
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None

    class Config:
        from_attributes = True

class PipelineRunBase(BaseModel):
    commit_sha: str
    branch: str

class PipelineRunCreate(PipelineRunBase):
    repository_full_name: str
    triggered_by: Optional[str] = None

class PipelineRunResponse(PipelineRunBase):
    id: UUID
    status: str
    triggered_by: Optional[str] = None
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    created_at: datetime
    steps: List[StepResponse] = []

    class Config:
        from_attributes = True

class RepositoryResponse(BaseModel):
    id: UUID
    name: str
    full_name: str
    clone_url: str
    created_at: datetime

    class Config:
        from_attributes = True
