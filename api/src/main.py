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
