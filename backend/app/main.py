"""
Smart Garbage Chute System - FastAPI Backend
Central orchestrator for IoT device management, alerts, AI detections, and OTA updates.
"""

from contextlib import asynccontextmanager
from datetime import datetime
import json
import asyncio
import random
from typing import List

from fastapi import FastAPI, Depends, HTTPException, WebSocket, WebSocketDisconnect, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.db.session import get_db, engine, AsyncSessionLocal
from app.db.base import Base
from app.models import (
    User, Building, Floor, Room, Device, SensorEvent, Alert, 
    AiEvent, MaintenanceLog, FirmwareVersion, OtaJob, Notification
)
from app.schemas import (
    LoginRequest, TokenResponse, SummaryOut, AlertOut, DeviceOut, 
    RoomOut, SensorEventOut
)
from app.core.security import create_access_token, hash_password, verify_password
from app.services.broadcaster import broadcaster
from app.services.mqtt_service import mqtt_service
from app.api.routers import auth, summary, alerts, devices, health, registry, ota, telemetry

# =========================================================
# LIFECYCLE & STARTUP
# =========================================================

async def init_db():
    """Create tables and seed demo data."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    async with AsyncSessionLocal() as session:
        # Check if admin exists
        admin = (await session.execute(select(User).where(User.email == "admin@alghurair.local"))).scalar_one_or_none()
        if not admin:
            # Create admin user
            admin_user = User(
                email="admin@alghurair.local",
                full_name="System Administrator",
                password_hash=hash_password("Admin@12345"),
                role="admin",
                is_active=True
            )
            session.add(admin_user)
            await session.commit()
        
        # Seed buildings and structure if empty
        building_count = (await session.execute(select(func.count(Building.id)))).scalar()
        if building_count == 0:
            # Create 2 buildings
            bldg1 = Building(code="BLK-01", name="Block A - Al Ghurair")
            bldg2 = Building(code="BLK-02", name="Block B - Al Ghurair")
            session.add_all([bldg1, bldg2])
            await session.flush()
            
            # Create floors
            for b in [bldg1, bldg2]:
                for level in [1, 2, 3]:
                    floor = Floor(building=b, level=level, name=f"Level {level}")
                    session.add(floor)
            
            await session.flush()
            
            # Create rooms and devices
            floors = (await session.execute(select(Floor))).scalars().all()
            room_counter = 1
            for floor in floors:
                for room_num in range(1, 6):
                    room_code = f"CHR_{room_counter:02d}"
                    room = Room(
                        floor=floor,
                        room_code=room_code,
                        name=f"Chute Room {room_counter}",
                        zone="chute-room"
                    )
                    session.add(room)
                    await session.flush()
                    
                    # Add device
                    device = Device(
                        room_id=room.id,
                        device_id=f"ESP32-{room_counter:02d}",
                        device_type="esp32-s3-poe",
                        firmware_version="1.2.1",
                        status="online",
                        last_seen_at=datetime.utcnow()
                    )
                    session.add(device)
                    room_counter += 1
            
            # Create firmware versions
            fw = FirmwareVersion(
                version="1.2.1",
                build_sha="abc123def456",
                artifact_url="https://example.com/firmware/v1.2.1.bin",
                is_active=True
            )
            session.add(fw)
            
            await session.commit()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan: startup and shutdown."""
    # Startup
    await init_db()
    await broadcaster.connect()
    mqtt_service.start()  # Start MQTT consumer
    yield
    # Shutdown
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
        "timestamp": datetime.utcnow().isoformat()
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

# =========================================================
# SIMULATION MODE
# =========================================================
# Provides fake telemetry, alerts, and AI detections for demo mode

simulation_active = False
simulation_task = None

async def simulation_loop(db: AsyncSession):
    """Generate simulated sensor events and alerts."""
    global simulation_active
    
    while simulation_active:
        try:
            # Get all rooms
            rooms = (await db.execute(select(Room))).scalars().all()
            
            if not rooms:
                await asyncio.sleep(5)
                continue
            
            # Pick random room and event
            room = random.choice(rooms)
            event_types = ["blockage", "overflow", "leak", "door_open", "motion"]
            event_type = random.choice(event_types)
            
            # Create sensor event
            sensor_event = SensorEvent(
                room_id=room.id,
                event_type=event_type,
                payload={
                    "sensor": event_type,
                    "timestamp": datetime.utcnow().isoformat()
                },
                severity=random.choice(["low", "medium", "high"]) if random.random() > 0.7 else "info"
            )
            db.add(sensor_event)
            
            # Maybe create an alert
            if random.random() > 0.6:
                alert = Alert(
                    room_id=room.id,
                    source="sensor",
                    category=event_type,
                    message=f"Simulated {event_type} in {room.name}",
                    severity=random.choice(["low", "medium", "high"])
                )
                db.add(alert)
                
                # Broadcast alert
                await broadcaster.publish(
                    "alerts",
                    json.dumps({
                        "type": "alert",
                        "id": alert.id,
                        "severity": alert.severity,
                        "message": alert.message,
                        "room_id": room.id
                    })
                )
            
            await db.commit()
            
            # Broadcast sensor telemetry
            await broadcaster.publish(
                "telemetry",
                json.dumps({
                    "type": "telemetry",
                    "room_id": room.id,
                    "event_type": event_type,
                    "timestamp": datetime.utcnow().isoformat()
                })
            )
            
            await asyncio.sleep(random.uniform(3, 8))
        
        except Exception as e:
            print(f"Simulation error: {e}")
            await asyncio.sleep(5)

@app.post("/api/simulation/start")
async def simulation_start(db: AsyncSession = Depends(get_db)):
    """Start simulation mode."""
    global simulation_active, simulation_task
    
    if simulation_active:
        return {"ok": False, "message": "Simulation already running"}
    
    simulation_active = True
    simulation_task = asyncio.create_task(simulation_loop(db))
    
    return {"ok": True, "message": "Simulation started"}

@app.post("/api/simulation/stop")
async def simulation_stop():
    """Stop simulation mode."""
    global simulation_active, simulation_task
    
    if not simulation_active:
        return {"ok": False, "message": "Simulation not running"}
    
    simulation_active = False
    if simulation_task:
        simulation_task.cancel()
        try:
            await simulation_task
        except asyncio.CancelledError:
            pass
    
    return {"ok": True, "message": "Simulation stopped"}

@app.post("/api/simulation/emit")
async def simulation_emit(
    room_id: int = Query(...),
    event_type: str = Query(...),
    severity: str = Query("medium"),
    db: AsyncSession = Depends(get_db)
):
    """Manually emit a simulation event."""
    room = (await db.execute(select(Room).where(Room.id == room_id))).scalar_one_or_none()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    # Create sensor event
    sensor_event = SensorEvent(
        room_id=room.id,
        event_type=event_type,
        payload={"source": "manual_sim", "timestamp": datetime.utcnow().isoformat()},
        severity=severity
    )
    db.add(sensor_event)
    
    # Create alert if severity is not info
    if severity != "info":
        alert = Alert(
            room_id=room.id,
            source="simulation",
            category=event_type,
            message=f"Simulated {event_type} in {room.name}",
            severity=severity
        )
        db.add(alert)
        
        await broadcaster.publish(
            "alerts",
            json.dumps({
                "type": "alert",
                "event_type": event_type,
                "severity": severity,
                "room_id": room.id,
                "timestamp": datetime.utcnow().isoformat()
            })
        )
    
    await db.commit()
    
    return {"ok": True, "event_type": event_type, "room_id": room_id}