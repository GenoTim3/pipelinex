"""
GitHub webhook endpoints.
"""

from fastapi import APIRouter, Request, HTTPException, Header, Depends, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
import logging

from api.src.db.database import get_db
from api.src.models.pipeline import Repository, PipelineRun, PipelineStep
from api.src.services.github import (
    verify_signature,
    parse_webhook_payload,
    clone_repository,
    fetch_pipeline_config,
    cleanup_repo,
)
from api.src.services.pipeline_parser import parse_pipeline_dict, PipelineConfigError
from api.src.services.queue import enqueue_pipeline_run

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/webhooks", tags=["webhooks"])

async def process_push_event(
    payload: dict,
    db: AsyncSession,
):
    """Process GitHub push event and create pipeline run."""
    
    # Parse webhook payload
    webhook_data = parse_webhook_payload(payload)
    
    if not webhook_data["commit_sha"]:
        logger.warning("No commit SHA in webhook payload")
        return {"status": "skipped", "reason": "No commit SHA"}
    
    # Skip if branch is not main/master (configurable later)
    # if webhook_data["branch"] not in ["main", "master"]:
    #     return {"status": "skipped", "reason": f"Branch {webhook_data['branch']} not configured"}
    
    # Get or create repository
    repo_query = select(Repository).where(
        Repository.full_name == webhook_data["repo_full_name"]
    )
    result = await db.execute(repo_query)
    repository = result.scalar_one_or_none()
    
    if not repository:
        repository = Repository(
            name=webhook_data["repo_name"],
            full_name=webhook_data["repo_full_name"],
            clone_url=webhook_data["clone_url"],
        )
        db.add(repository)
        await db.flush()
    
    # Clone repo and fetch pipeline config
    repo_path = None
    try:
        repo_path = await clone_repository(
            webhook_data["clone_url"],
            webhook_data["commit_sha"]
        )
        
        pipeline_config = await fetch_pipeline_config(repo_path)
        
        if not pipeline_config:
            logger.info(f"No pipeline config found in {webhook_data['repo_full_name']}")
            return {"status": "skipped", "reason": "No pipeline configuration found"}
        
        # Validate config
        validated_config = parse_pipeline_dict(pipeline_config)
        
    except PipelineConfigError as e:
        logger.error(f"Invalid pipeline config: {e}")
        return {"status": "error", "reason": str(e)}
    except Exception as e:
        logger.error(f"Failed to process repository: {e}")
        return {"status": "error", "reason": str(e)}
    finally:
        if repo_path:
            cleanup_repo(repo_path)
    
    # Create pipeline run
    pipeline_run = PipelineRun(
        repository_id=repository.id,
        commit_sha=webhook_data["commit_sha"],
        branch=webhook_data["branch"],
        status="queued",
        triggered_by=webhook_data["pusher"],
        config=validated_config,
    )
    db.add(pipeline_run)
    await db.flush()
    
    # Create pipeline steps
    for i, step_config in enumerate(validated_config["steps"]):
        step = PipelineStep(
            run_id=pipeline_run.id,
            name=step_config["name"],
            image=step_config["image"],
            commands=step_config["commands"],
            status="pending",
            step_order=i,
        )
        db.add(step)
    
    await db.commit()
    
    # Enqueue for processing
    await enqueue_pipeline_run(
        run_id=str(pipeline_run.id),
        config=validated_config,
        repo_info=webhook_data,
    )
    
    logger.info(f"Pipeline run {pipeline_run.id} created and queued")
    
    return {
        "status": "queued",
        "run_id": str(pipeline_run.id),
        "steps": len(validated_config["steps"]),
    }

@router.post("/github")
async def github_webhook(
    request: Request,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    x_hub_signature_256: Optional[str] = Header(None),
    x_github_event: Optional[str] = Header(None),
):
    """
    Receive GitHub webhook events.
    """
    # Get raw body for signature verification
    body = await request.body()
    
    # Verify signature
    if x_hub_signature_256:
        if not verify_signature(body, x_hub_signature_256):
            raise HTTPException(status_code=401, detail="Invalid signature")
    
    # Parse JSON payload
    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON payload")
    
    # Handle different event types
    if x_github_event == "ping":
        return {"status": "pong", "message": "Webhook configured successfully"}
    
    if x_github_event == "push":
        result = await process_push_event(payload, db)
        return result
    
    # Ignore other events
    return {
        "status": "ignored",
        "event": x_github_event,
        "message": f"Event type '{x_github_event}' not handled"
    }

@router.get("/test")
async def test_webhook():
    """Test endpoint to verify webhook route is working."""
    return {"status": "ok", "message": "Webhook endpoint is ready"}
