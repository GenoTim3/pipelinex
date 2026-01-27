from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    database_url: str = "postgresql://pipelinex:pipelinex@localhost:5432/pipelinex"
    redis_url: str = "redis://localhost:6379/0"
    
    # Kubernetes settings
    k8s_namespace: str = "pipelinex"
    k8s_in_cluster: bool = False  # Set True when running inside K8s
    
    # Job settings
    job_timeout: int = 600  # 10 minutes default
    job_ttl_after_finished: int = 300  # Clean up jobs after 5 min
    
    class Config:
        env_file = ".env"

@lru_cache()
def get_settings() -> Settings:
    return Settings()
