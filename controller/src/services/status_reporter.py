"""
Report pipeline and step status to database.
"""

import logging
from datetime import datetime
from typing import Optional
from sqlalchemy import create_engine, update
from sqlalchemy.orm import sessionmaker

from controller.src.config import get_settings
from controller.src.models.step import StepStatus

logger = logging.getLogger(__name__)
settings = get_settings()

# Sync database connection for controller
engine = create_engine(settings.database_url)
SessionLocal = sessionmaker(bind=engine)

def update_run_status(
    run_id: str,
    status: str,
    started_at: Optional[datetime] = None,
    finished_at: Optional[datetime] = None,
):
    """Update pipeline run status in database."""
    from controller.src.models.db import PipelineRun
    
    with SessionLocal() as session:
        values = {"status": status, "updated_at": datetime.utcnow()}
        
        if started_at:
            values["started_at"] = started_at
        if finished_at:
            values["finished_at"] = finished_at
        
        session.execute(
            update(PipelineRun)
            .where(PipelineRun.id == run_id)
            .values(**values)
        )
        session.commit()
        logger.info(f"Updated run {run_id} status to {status}")

def update_step_status(
    run_id: str,
    step_order: int,
    status: str,
    logs: Optional[str] = None,
    started_at: Optional[datetime] = None,
    finished_at: Optional[datetime] = None,
):
    """Update pipeline step status in database."""
    from controller.src.models.db import PipelineStep
    
    with SessionLocal() as session:
        values = {"status": status, "updated_at": datetime.utcnow()}
        
        if logs is not None:
            values["logs"] = logs
        if started_at:
            values["started_at"] = started_at
        if finished_at:
            values["finished_at"] = finished_at
        
        session.execute(
            update(PipelineStep)
            .where(PipelineStep.run_id == run_id)
            .where(PipelineStep.step_order == step_order)
            .values(**values)
        )
        session.commit()
        logger.debug(f"Updated step {step_order} of run {run_id} to {status}")

def get_run_steps(run_id: str):
    """Get all steps for a run."""
    from controller.src.models.db import PipelineStep
    
    with SessionLocal() as session:
        steps = session.query(PipelineStep).filter(
            PipelineStep.run_id == run_id
        ).order_by(PipelineStep.step_order).all()
        
        return [
            {
                "order": s.step_order,
                "name": s.name,
                "image": s.image,
                "commands": s.commands,
                "status": s.status,
            }
            for s in steps
        ]
