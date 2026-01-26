"""Tests for webhook handling."""

import pytest
from api.src.services.github import parse_webhook_payload, verify_signature

def test_parse_push_payload():
    payload = {
        "ref": "refs/heads/main",
        "repository": {
            "name": "test-repo",
            "full_name": "user/test-repo",
            "clone_url": "https://github.com/user/test-repo.git",
        },
        "head_commit": {
            "id": "abc123def456",
            "message": "Test commit",
        },
        "pusher": {
            "name": "testuser",
        },
    }
    
    result = parse_webhook_payload(payload)
    
    assert result["repo_name"] == "test-repo"
    assert result["repo_full_name"] == "user/test-repo"
    assert result["branch"] == "main"
    assert result["commit_sha"] == "abc123def456"
    assert result["pusher"] == "testuser"

def test_parse_payload_with_after():
    """Test fallback to 'after' field for commit SHA."""
    payload = {
        "ref": "refs/heads/feature",
        "after": "xyz789",
        "repository": {
            "name": "repo",
            "full_name": "user/repo",
            "clone_url": "https://github.com/user/repo.git",
        },
        "head_commit": {},
        "pusher": {"name": "user"},
    }
    
    result = parse_webhook_payload(payload)
    assert result["commit_sha"] == "xyz789"
    assert result["branch"] == "feature"

def test_verify_signature_without_secret():
    """When no secret is configured, verification should pass."""
    # This test assumes GITHUB_WEBHOOK_SECRET is not set
    result = verify_signature(b"payload", "sha256=anything")
    assert result is True
