FROM python:3.11-slim
WORKDIR /app
COPY pyproject.toml /app/
RUN pip install --no-cache-dir fastapi uvicorn[standard] sqlalchemy asyncpg alembic pydantic pydantic-settings python-jose[cryptography] passlib[bcrypt] python-multipart redis httpx orjson paho-mqtt structlog prometheus-client tenacity email-validator bcrypt==4.3.0
COPY app /app/app
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]



