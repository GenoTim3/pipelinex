#!/bin/bash

# PipelineX Phase 1 Setup Script
# Run from the pipelinex root directory

set -e

echo "🚀 Setting up Phase 1: API + Database"

# ============================================
# .env.example
# ============================================
cat > .env.example << 'EOF'
DATABASE_URL=postgresql://pipelinex:pipelinex@postgres:5432/pipelinex
REDIS_URL=redis://redis:6379/0
GITHUB_WEBHOOK_SECRET=your-webhook-secret-here
API_HOST=0.0.0.0
API_PORT=8000
EOF

echo "✅ .env.example"

# ============================================
# Database Schema
# ============================================
cat > db/migrations/001_initial_schema.sql << 'EOF'
-- PipelineX Database Schema

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Repositories table
CREATE TABLE repositories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL UNIQUE,
    clone_url VARCHAR(500) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Pipeline runs table
CREATE TABLE pipeline_runs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    repository_id UUID REFERENCES repositories(id) ON DELETE CASCADE,
    commit_sha VARCHAR(40) NOT NULL,
    branch VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    triggered_by VARCHAR(255),
    config JSONB,
    started_at TIMESTAMP,
    finished_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Pipeline steps table
CREATE TABLE pipeline_steps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    run_id UUID REFERENCES pipeline_runs(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    image VARCHAR(255) NOT NULL,
    commands JSONB NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    step_order INTEGER NOT NULL,
    logs TEXT,
    started_at TIMESTAMP,
    finished_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_pipeline_runs_repository ON pipeline_runs(repository_id);
CREATE INDEX idx_pipeline_runs_status ON pipeline_runs(status);
CREATE INDEX idx_pipeline_steps_run ON pipeline_steps(run_id);
CREATE INDEX idx_pipeline_steps_status ON pipeline_steps(status);
EOF

echo "✅ db/migrations/001_initial_schema.sql"

# ============================================
# db/init.sql
# ============================================
cat > db/init.sql << 'EOF'
-- Initialize database
\i /docker-entrypoint-initdb.d/migrations/001_initial_schema.sql
EOF

echo "✅ db/init.sql"

# ============================================
# API Requirements
# ============================================
cat > api/requirements.txt << 'EOF'
fastapi==0.109.0
uvicorn[standard]==0.27.0
sqlalchemy==2.0.25
asyncpg==0.29.0
psycopg2-binary==2.9.9
pydantic==2.5.3
pydantic-settings==2.1.0
redis==5.0.1
httpx==0.26.0
PyYAML==6.0.1
python-dotenv==1.0.0
EOF

echo "✅ api/requirements.txt"

# ============================================
# API Config
# ============================================
cat > api/src/config.py << 'EOF'
from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    database_url: str = "postgresql://pipelinex:pipelinex@localhost:5432/pipelinex"
    redis_url: str = "redis://localhost:6379/0"
    github_webhook_secret: str = ""
    api_host: str = "0.0.0.0"
    api_port: int = 8000

    class Config:
        env_file = ".env"

@lru_cache()
def get_settings() -> Settings:
    return Settings()
EOF

echo "✅ api/src/config.py"

# ============================================
# API Database Connection
# ============================================
cat > api/src/db/database.py << 'EOF'
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from api.src.config import get_settings

settings = get_settings()

# Convert postgresql:// to postgresql+asyncpg://
db_url = settings.database_url.replace("postgresql://", "postgresql+asyncpg://")

engine = create_async_engine(db_url, echo=True)

async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

Base = declarative_base()

async def get_db():
    async with async_session() as session:
        try:
            yield session
        finally:
            await session.close()

async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
EOF

echo "✅ api/src/db/database.py"

# ============================================
# API Models - Pipeline
# ============================================
cat > api/src/models/pipeline.py << 'EOF'
from sqlalchemy import Column, String, DateTime, ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid

from api.src.db.database import Base

class Repository(Base):
    __tablename__ = "repositories"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    full_name = Column(String(255), nullable=False, unique=True)
    clone_url = Column(String(500), nullable=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    runs = relationship("PipelineRun", back_populates="repository")

class PipelineRun(Base):
    __tablename__ = "pipeline_runs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    repository_id = Column(UUID(as_uuid=True), ForeignKey("repositories.id", ondelete="CASCADE"))
    commit_sha = Column(String(40), nullable=False)
    branch = Column(String(255), nullable=False)
    status = Column(String(50), default="pending")
    triggered_by = Column(String(255))
    config = Column(JSONB)
    started_at = Column(DateTime)
    finished_at = Column(DateTime)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    repository = relationship("Repository", back_populates="runs")
    steps = relationship("PipelineStep", back_populates="run")

class PipelineStep(Base):
    __tablename__ = "pipeline_steps"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    run_id = Column(UUID(as_uuid=True), ForeignKey("pipeline_runs.id", ondelete="CASCADE"))
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

    run = relationship("PipelineRun", back_populates="steps")
EOF

echo "✅ api/src/models/pipeline.py"

# ============================================
# API Models - Run (Pydantic schemas)
# ============================================
cat > api/src/models/run.py << 'EOF'
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
EOF

echo "✅ api/src/models/run.py"

# ============================================
# API Models __init__
# ============================================
cat > api/src/models/__init__.py << 'EOF'
from api.src.models.pipeline import Repository, PipelineRun, PipelineStep
from api.src.models.run import (
    PipelineRunCreate,
    PipelineRunResponse,
    StepResponse,
    RepositoryResponse
)

__all__ = [
    "Repository",
    "PipelineRun", 
    "PipelineStep",
    "PipelineRunCreate",
    "PipelineRunResponse",
    "StepResponse",
    "RepositoryResponse"
]
EOF

echo "✅ api/src/models/__init__.py"

# ============================================
# API Routes - Health
# ============================================
cat > api/src/routes/health.py << 'EOF'
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from api.src.db.database import get_db

router = APIRouter(tags=["health"])

@router.get("/health")
async def health_check():
    return {"status": "healthy", "service": "pipelinex-api"}

@router.get("/health/db")
async def db_health_check(db: AsyncSession = Depends(get_db)):
    try:
        await db.execute(text("SELECT 1"))
        return {"status": "healthy", "database": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "database": str(e)}
EOF

echo "✅ api/src/routes/health.py"

# ============================================
# API Routes - Pipelines
# ============================================
cat > api/src/routes/pipelines.py << 'EOF'
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
EOF

echo "✅ api/src/routes/pipelines.py"

# ============================================
# API Routes - Webhooks (placeholder for Phase 2)
# ============================================
cat > api/src/routes/webhooks.py << 'EOF'
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
EOF

echo "✅ api/src/routes/webhooks.py"

# ============================================
# API Routes __init__
# ============================================
cat > api/src/routes/__init__.py << 'EOF'
from api.src.routes.health import router as health_router
from api.src.routes.pipelines import router as pipelines_router
from api.src.routes.webhooks import router as webhooks_router

__all__ = ["health_router", "pipelines_router", "webhooks_router"]
EOF

echo "✅ api/src/routes/__init__.py"

# ============================================
# API Services (placeholders for Phase 2)
# ============================================
cat > api/src/services/github.py << 'EOF'
"""
GitHub service for webhook validation and repo cloning.
Implementation in Phase 2.
"""

import hmac
import hashlib

def verify_signature(payload: bytes, signature: str, secret: str) -> bool:
    """Verify GitHub webhook signature."""
    expected = "sha256=" + hmac.new(
        secret.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)

async def clone_repository(clone_url: str, commit_sha: str) -> str:
    """Clone repository to temporary directory. Returns path."""
    # TODO: Implement in Phase 2
    pass

async def fetch_pipeline_config(repo_path: str) -> dict:
    """Read .pipeline.yml from repository."""
    # TODO: Implement in Phase 2
    pass
EOF

echo "✅ api/src/services/github.py"

cat > api/src/services/pipeline_parser.py << 'EOF'
"""
Pipeline YAML parser.
Implementation in Phase 2.
"""

import yaml
from typing import List, Dict, Any

def parse_pipeline_config(yaml_content: str) -> Dict[str, Any]:
    """Parse pipeline YAML configuration."""
    config = yaml.safe_load(yaml_content)
    return validate_config(config)

def validate_config(config: Dict[str, Any]) -> Dict[str, Any]:
    """Validate pipeline configuration structure."""
    if not config:
        raise ValueError("Empty pipeline configuration")
    
    if "steps" not in config:
        raise ValueError("Pipeline must have 'steps' defined")
    
    for i, step in enumerate(config["steps"]):
        if "name" not in step:
            raise ValueError(f"Step {i} missing 'name'")
        if "image" not in step:
            raise ValueError(f"Step {i} missing 'image'")
        if "commands" not in step:
            raise ValueError(f"Step {i} missing 'commands'")
    
    return config
EOF

echo "✅ api/src/services/pipeline_parser.py"

cat > api/src/services/queue.py << 'EOF'
"""
Redis queue service for pipeline jobs.
Implementation in Phase 2.
"""

import redis.asyncio as redis
import json
from typing import Dict, Any

from api.src.config import get_settings

settings = get_settings()

async def get_redis_client():
    """Get async Redis client."""
    return redis.from_url(settings.redis_url)

async def enqueue_pipeline_run(run_id: str, config: Dict[str, Any]):
    """Add pipeline run to processing queue."""
    client = await get_redis_client()
    job = {"run_id": run_id, "config": config}
    await client.lpush("pipeline_jobs", json.dumps(job))
    await client.close()

async def dequeue_pipeline_run() -> Dict[str, Any] | None:
    """Get next pipeline run from queue."""
    client = await get_redis_client()
    result = await client.brpop("pipeline_jobs", timeout=5)
    await client.close()
    if result:
        return json.loads(result[1])
    return None
EOF

echo "✅ api/src/services/queue.py"

cat > api/src/services/__init__.py << 'EOF'
from api.src.services.github import verify_signature
from api.src.services.pipeline_parser import parse_pipeline_config
from api.src.services.queue import enqueue_pipeline_run, dequeue_pipeline_run

__all__ = [
    "verify_signature",
    "parse_pipeline_config", 
    "enqueue_pipeline_run",
    "dequeue_pipeline_run"
]
EOF

echo "✅ api/src/services/__init__.py"

# ============================================
# API DB __init__
# ============================================
cat > api/src/db/__init__.py << 'EOF'
from api.src.db.database import get_db, init_db, Base, engine

__all__ = ["get_db", "init_db", "Base", "engine"]
EOF

echo "✅ api/src/db/__init__.py"

# ============================================
# API Main
# ============================================
cat > api/src/main.py << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from api.src.config import get_settings
from api.src.routes import health_router, pipelines_router, webhooks_router

settings = get_settings()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print("🚀 Starting PipelineX API")
    yield
    # Shutdown
    print("👋 Shutting down PipelineX API")

app = FastAPI(
    title="PipelineX",
    description="Lightweight CI/CD Pipeline Runner",
    version="0.1.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(health_router)
app.include_router(pipelines_router, prefix="/api")
app.include_router(webhooks_router, prefix="/api")

@app.get("/")
async def root():
    return {
        "name": "PipelineX",
        "version": "0.1.0",
        "docs": "/docs"
    }
EOF

echo "✅ api/src/main.py"

# ============================================
# API src __init__
# ============================================
cat > api/src/__init__.py << 'EOF'
EOF

echo "✅ api/src/__init__.py"

# ============================================
# API Dockerfile
# ============================================
cat > api/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Set Python path
ENV PYTHONPATH=/app

EXPOSE 8000

CMD ["uvicorn", "api.src.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

echo "✅ api/Dockerfile"

# ============================================
# Docker Compose
# ============================================
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  api:
    build:
      context: .
      dockerfile: api/Dockerfile
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://pipelinex:pipelinex@postgres:5432/pipelinex
      - REDIS_URL=redis://redis:6379/0
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
    volumes:
      - ./api:/app/api
    networks:
      - pipelinex

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: pipelinex
      POSTGRES_PASSWORD: pipelinex
      POSTGRES_DB: pipelinex
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./db/migrations:/docker-entrypoint-initdb.d/migrations
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U pipelinex"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - pipelinex

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - pipelinex

volumes:
  postgres_data:
  redis_data:

networks:
  pipelinex:
    driver: bridge
EOF

echo "✅ docker-compose.yml"

echo ""
echo "============================================"
echo "🎉 Phase 1 setup complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Run: docker-compose up --build"
echo "  2. Visit: http://localhost:8000"
echo "  3. API docs: http://localhost:8000/docs"
echo "  4. Health check: http://localhost:8000/health"
echo ""
