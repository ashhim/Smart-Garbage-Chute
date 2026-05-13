from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    env: str = "development"
    secret_key: str = "change-me"
    jwt_alg: str = "HS256"
    access_token_expire_minutes: int = 480
    database_url: str = "postgresql+asyncpg://postgres:postgres@postgres:5432/garbage_chute"
    redis_url: str = "redis://redis:6379/0"
    mqtt_url: str = "mqtt://mosquitto:1883"
    mqtt_host: str = "mosquitto"
    mqtt_port: int = 1883
    backend_cors_origins: str = "http://localhost:3000,http://localhost:8080"
    api_base_url: str = "http://backend:8000"
    ai_service_url: str = "http://ai-service:8001"

    @property
    def cors_origins(self):
        return [x.strip() for x in self.backend_cors_origins.split(",") if x.strip()]

@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
