"""
Database models for controller (sync version).
"""

from sqlalchemy import Column, String, DateTime, ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import declarative_base
from sqlalchemy.sql import func
import uuid

Base = declarative_base()

class PipelineRun(Base):
    __tablename__ = "pipeline_runs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    repository_id = Column(UUID(as_uuid=True))
    commit_sha = Column(String(40), nullable=False)
    branch = Column(String(255), nullable=False)
    status = Column(String(50), default="pending")
    triggered_by = Column(String(255))
    config = Column(JSONB)
    started_at = Column(DateTime)
    finished_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

class PipelineStep(Base):
    __tablename__ = "pipeline_steps"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    run_id = Column(UUID(as_uuid=True), ForeignKey("pipeline_runs.id"))
    name = Column(String(255), nullable=False)
    image = Column(String(255), nullable=False)
    commands = Column(JSONB, nullable=False)
    status = Column(String(50), default="pending")
    step_order = Column(Integer, nullable=False)
    logs = Column(Text)
    started_at = Column(DateTime)
    finished_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
