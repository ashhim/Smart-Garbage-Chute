from contextlib import asynccontextmanager
from datetime import datetime, timezone
import asyncio
import logging
import random

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import hash_password, create_access_token
from app.db.session import engine, AsyncSessionLocal
from app.db.base import Base
from app.models import User, Building, Floor, Room, Device, Alert
from app.api.routers import auth, registry, alerts, ota, telemetry, summary, health
from app.services.alert_engine import alert_engine
from app.services.broadcaster import broadcaster
from app.services.mqtt_service import mqtt_service

settings = get_settings()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def seed_data():
    async with AsyncSessionLocal() as db:
        admin = (await db.execute(select(User).where(User.email == "admin@alghurair.local"))).scalar_one_or_none()
        if not admin:
            db.add(User(email="admin@alghurair.local", full_name="Control Room Admin", password_hash=hash_password("Admin@12345"), role="admin"))
        building = (await db.execute(select(Building).where(Building.code == "B1"))).scalar_one_or_none()
        if not building:
            building = Building(code="B1", name="Al Ghurair Tower A")
            db.add(building)
            await db.flush()
            floor = Floor(building_id=building.id, level=1, name="Floor 1")
            db.add(floor)
            await db.flush()
            room = Room(floor_id=floor.id, room_code="CHR_01", name="Chute Room 01")
            db.add(room)
            await db.flush()
            db.add(Device(room_id=room.id, device_id="ESP32-CHR-01", device_type="esp32-s3-poe", firmware_version="1.0.0"))
        await db.commit()

async def telemetry_simulator():
    while True:
        try:
            async with AsyncSessionLocal() as db:
                room = (await db.execute(select(Room).where(Room.room_code == "CHR_01"))).scalar_one()
                device = (await db.execute(select(Device).where(Device.device_id == "ESP32-CHR-01"))).scalar_one()
                rnd = random.random()
                door_open = rnd < 0.2
                blockage = rnd > 0.82
                leak = rnd > 0.93
                payload = {
                    "room_id": room.room_code,
                    "door_open": door_open,
                    "blockage": blockage,
                    "leak_detected": leak,
                    "ultrasonic_distance_cm": round(random.uniform(5, 120), 1),
                    "motion_detected": rnd > 0.5,
                    "timestamp": int(datetime.now(timezone.utc).timestamp()),
                }
                await alert_engine.ingest_sensor_event(db, room.id, device.id, "door_prolonged_open" if door_open and rnd > 0.6 else ("blockage" if blockage else ("leak" if leak else "heartbeat")), payload, severity="high" if blockage or leak else "medium")
                device.last_seen_at = datetime.now(timezone.utc)
                await db.commit()
                await broadcaster.publish("telemetry", {"type": "telemetry", "payload": payload})
        except Exception as exc:
            logger.warning("telemetry simulator error: %s", exc)
        await asyncio.sleep(5)

@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await seed_data()
    mqtt_service.start()
    task = asyncio.create_task(telemetry_simulator())
    yield
    task.cancel()

app = FastAPI(title="Smart Garbage Chute System API", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router, prefix="/api")
app.include_router(registry.router, prefix="/api")
app.include_router(alerts.router, prefix="/api")
app.include_router(ota.router, prefix="/api")
app.include_router(summary.router, prefix="/api")
app.include_router(telemetry.router, prefix="/api")

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    """WebSocket gateway for real-time updates (telemetry, alerts, OTA)."""
    await ws.accept()
    logger.info("ws.client.connected")
    
    q1 = await broadcaster.subscribe("telemetry")
    q2 = await broadcaster.subscribe("alerts")
    q3 = await broadcaster.subscribe("ota")
    
    try:
        while True:
            done, pending = await asyncio.wait(
                [
                    asyncio.create_task(q1.get()),
                    asyncio.create_task(q2.get()),
                    asyncio.create_task(q3.get())
                ],
                return_when=asyncio.FIRST_COMPLETED
            )
            
            for task in done:
                try:
                    message = task.result()
                    await ws.send_json(message)
                except Exception as exc:
                    logger.warning("ws.send_failed", exc_info=exc)
                    break
            
            # Clean up pending tasks
            for task in pending:
                task.cancel()
                
    except WebSocketDisconnect:
        logger.info("ws.client.disconnected")
    except Exception as exc:
        logger.exception("ws.error", exc_info=exc)
        try:
            await ws.close(code=1011, reason="Internal server error")
        except:
            pass
    finally:
        await broadcaster.unsubscribe("telemetry", q1)
        await broadcaster.unsubscribe("alerts", q2)
        await broadcaster.unsubscribe("ota", q3)
        logger.info("ws.client.cleanup")
