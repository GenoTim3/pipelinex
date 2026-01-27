"""
Step execution models.
"""

from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from datetime import datetime
from enum import Enum

class StepStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    CANCELLED = "cancelled"

class StepConfig(BaseModel):
    name: str
    image: str
    commands: List[str]
    env: Dict[str, str] = {}
    timeout: int = 600

class StepResult(BaseModel):
    step_order: int
    name: str
    status: StepStatus
    logs: Optional[str] = None
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    error: Optional[str] = None

class PipelineJob(BaseModel):
    run_id: str
    config: Dict[str, Any]
    repo_info: Dict[str, Any]
    queued_at: str
