"""
Smart Garbage Chute System - FastAPI Backend
Central orchestrator for IoT device management, alerts, AI detections, and OTA updates.
"""

from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import Body, FastAPI, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.db.session import AsyncSessionLocal, engine, get_db
from app.db.base import Base
from app.models import Room
from app.schemas import SimulationEmitRequest
from app.api.deps import get_current_user
from app.services.broadcaster import broadcaster
from app.services.demo_data import ensure_demo_platform
from app.services.mqtt_service import mqtt_service
from app.services.simulation_service import simulation_service
from app.api.routers import auth, summary, alerts, devices, health, registry, ota, telemetry

# =========================================================
# LIFECYCLE & STARTUP
# =========================================================

async def init_db():
    """Create tables and seed demo data."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    async with AsyncSessionLocal() as session:
        await ensure_demo_platform(session)

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan: startup and shutdown."""
    # Startup
    await init_db()
    await broadcaster.connect()
    mqtt_service.start()  # Start MQTT consumer
    yield
    # Shutdown
    if simulation_service.active:
        await simulation_service.stop()
    await broadcaster.disconnect()

app = FastAPI(
    title="Smart Garbage Chute API",
    version="1.0.0",
    description="Industrial IoT platform for chute room monitoring, AI detection, and OTA management",
    lifespan=lifespan
)

# =========================================================
# CORS
# =========================================================

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# =========================================================
# ROUTER INCLUSION
# =========================================================

app.include_router(auth.router, prefix="/api")
app.include_router(summary.router, prefix="/api")
app.include_router(alerts.router, prefix="/api")
app.include_router(devices.router, prefix="/api")
app.include_router(health.router, prefix="/api")
app.include_router(registry.router, prefix="/api")
app.include_router(ota.router, prefix="/api")
app.include_router(telemetry.router, prefix="/api")

# =========================================================
# ROOT & HEALTH
# =========================================================

@app.get("/")
async def root():
    return {
        "status": "running",
        "service": "Smart Garbage Chute Backend",
        "version": "1.0.0"
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

# =========================================================
# WEBSOCKET GATEWAY
# =========================================================

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """Real-time event streaming via WebSocket."""
    await websocket.accept()
    
    # Subscribe to all channels
    await broadcaster.subscribe(websocket, "telemetry")
    await broadcaster.subscribe(websocket, "alerts")
    await broadcaster.subscribe(websocket, "ota")
    
    try:
        while True:
            # Listen for incoming messages (for future command support)
            data = await websocket.receive_text()
            # Echo or handle if needed
    except WebSocketDisconnect:
        await broadcaster.unsubscribe(websocket, "telemetry")
        await broadcaster.unsubscribe(websocket, "alerts")
        await broadcaster.unsubscribe(websocket, "ota")
    except Exception as e:
        print(f"WebSocket error: {e}")
        await websocket.close()

@app.post("/api/simulation/start")
async def simulation_start(user=Depends(get_current_user)):
    """Start simulation mode."""
    return await simulation_service.start()

@app.post("/api/simulation/stop")
async def simulation_stop(user=Depends(get_current_user)):
    """Stop simulation mode."""
    return await simulation_service.stop()

@app.post("/api/simulation/emit")
async def simulation_emit(
    request: SimulationEmitRequest | None = Body(default=None),
    room_id: int | None = Query(default=None),
    room_code: str | None = Query(default=None),
    event_type: str | None = Query(default=None),
    severity: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    user=Depends(get_current_user),
):
    """Manually emit a simulation event."""
    payload = request or SimulationEmitRequest(
        room_id=room_id,
        room_code=room_code,
        event_type=event_type or "heartbeat",
        severity=severity,
    )

    try:
        return await simulation_service.emit(
            db,
            room_id=payload.room_id,
            room_code=payload.room_code,
            event_type=payload.event_type,
            severity=payload.severity,
            source=payload.source,
            payload=payload.payload,
            confidence=payload.confidence,
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
