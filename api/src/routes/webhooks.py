from fastapi import APIRouter, Request, HTTPException, Header
from typing import Optional

router = APIRouter(prefix="/webhooks", tags=["webhooks"])

@router.post("/github")
async def github_webhook(
    request: Request,
    x_hub_signature_256: Optional[str] = Header(None),
    x_github_event: Optional[str] = Header(None)
):
    """
    Receive GitHub webhook events.
    Full implementation in Phase 2.
    """
    body = await request.json()
    
    return {
        "status": "received",
        "event": x_github_event,
        "message": "Webhook processing not yet implemented"
    }
