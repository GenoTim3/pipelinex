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
