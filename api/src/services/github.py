"""
GitHub service for webhook validation and repo operations.
"""

import hmac
import hashlib
import tempfile
import subprocess
import os
from typing import Optional, Dict, Any

import httpx
import yaml

from api.src.config import get_settings

settings = get_settings()

def verify_signature(payload: bytes, signature: str) -> bool:
    """Verify GitHub webhook signature."""
    if not settings.github_webhook_secret:
        # Skip verification if no secret configured (development)
        return True
    
    expected = "sha256=" + hmac.new(
        settings.github_webhook_secret.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)

async def clone_repository(clone_url: str, commit_sha: str) -> str:
    """
    Clone repository to temporary directory.
    Returns path to cloned repo.
    """
    temp_dir = tempfile.mkdtemp(prefix="pipelinex_")
    repo_path = os.path.join(temp_dir, "repo")
    
    try:
        # Clone the repository
        subprocess.run(
            ["git", "clone", "--depth", "1", clone_url, repo_path],
            check=True,
            capture_output=True,
            timeout=120
        )
        
        # Checkout specific commit if provided
        if commit_sha:
            subprocess.run(
                ["git", "fetch", "--depth", "1", "origin", commit_sha],
                cwd=repo_path,
                capture_output=True,
                timeout=60
            )
            subprocess.run(
                ["git", "checkout", commit_sha],
                cwd=repo_path,
                check=True,
                capture_output=True,
                timeout=30
            )
        
        return repo_path
    except subprocess.TimeoutExpired:
        raise Exception("Repository clone timed out")
    except subprocess.CalledProcessError as e:
        raise Exception(f"Failed to clone repository: {e.stderr.decode()}")

async def fetch_pipeline_config(repo_path: str) -> Optional[Dict[str, Any]]:
    """
    Read .pipeline.yml from repository.
    Returns parsed config or None if not found.
    """
    config_paths = [
        os.path.join(repo_path, ".pipeline.yml"),
        os.path.join(repo_path, ".pipeline.yaml"),
        os.path.join(repo_path, "pipeline.yml"),
        os.path.join(repo_path, "pipeline.yaml"),
    ]
    
    for config_path in config_paths:
        if os.path.exists(config_path):
            with open(config_path, "r") as f:
                return yaml.safe_load(f)
    
    return None

def parse_webhook_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Extract relevant info from GitHub webhook payload."""
    repo = payload.get("repository", {})
    head_commit = payload.get("head_commit", {})
    
    # Get branch from ref (refs/heads/main -> main)
    ref = payload.get("ref", "")
    branch = ref.replace("refs/heads/", "") if ref.startswith("refs/heads/") else ref
    
    return {
        "repo_name": repo.get("name", ""),
        "repo_full_name": repo.get("full_name", ""),
        "clone_url": repo.get("clone_url", ""),
        "commit_sha": head_commit.get("id", payload.get("after", "")),
        "branch": branch,
        "commit_message": head_commit.get("message", ""),
        "pusher": payload.get("pusher", {}).get("name", ""),
    }

def cleanup_repo(repo_path: str):
    """Clean up cloned repository."""
    import shutil
    try:
        if repo_path and os.path.exists(repo_path):
            # Get parent temp directory
            parent = os.path.dirname(repo_path)
            shutil.rmtree(parent)
    except Exception:
        pass  # Best effort cleanup
