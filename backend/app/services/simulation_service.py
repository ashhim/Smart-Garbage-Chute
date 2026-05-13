from __future__ import annotations

import asyncio
import random
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.db.session import AsyncSessionLocal
from app.models import AiEvent, Device, Floor, Room
from app.services.alert_engine import alert_engine
from app.services.broadcaster import broadcaster

SIMULATION_EVENT_LIBRARY: dict[str, dict[str, Any]] = {
    "heartbeat": {
        "severity": "info",
        "source": "telemetry",
        "message": "Heartbeat received from room controller.",
        "payload": lambda room, device: {
            "heartbeat": True,
            "controller_temp_c": round(random.uniform(31.5, 39.5), 1),
            "signal": "ethernet",
        },
    },
    "door_open": {
        "severity": "medium",
        "source": "sensor",
        "message": "Door opened for routine access.",
        "payload": lambda room, device: {
            "door_open": True,
            "door_open_seconds": random.randint(12, 48),
            "sensor": "magnetic_contact",
        },
    },
    "door_prolonged_open": {
        "severity": "high",
        "source": "sensor",
        "message": "Door has remained open beyond the configured threshold.",
        "payload": lambda room, device: {
            "door_open": True,
            "door_open_seconds": random.randint(150, 320),
            "sensor": "magnetic_contact",
        },
    },
    "blockage": {
        "severity": "high",
        "source": "sensor",
        "message": "Blockage pattern detected at chute inlet.",
        "payload": lambda room, device: {
            "blockage": True,
            "distance_cm": random.randint(8, 18),
            "sensor": "ultrasonic",
        },
    },
    "overflow": {
        "severity": "high",
        "source": "sensor",
        "message": "Overflow risk detected by controller and CCTV assist.",
        "payload": lambda room, device: {
            "overflow_percent": random.randint(82, 98),
            "sensor": "ultrasonic",
        },
    },
    "leak": {
        "severity": "critical",
        "source": "sensor",
        "message": "Liquid detected on the chute room floor.",
        "payload": lambda room, device: {
            "leak_detected": True,
            "sensor": "floor_probe",
            "wetness_level": random.randint(60, 100),
        },
    },
    "motion": {
        "severity": "info",
        "source": "ai",
        "message": "Motion detected in camera coverage area.",
        "payload": lambda room, device: {
            "motion_detected": True,
            "camera_id": f"CAM-{room.room_code}",
        },
    },
    "garbage_left": {
        "severity": "high",
        "source": "ai",
        "message": "Garbage bag left on floor near chute entrance.",
        "payload": lambda room, device: {
            "camera_id": f"CAM-{room.room_code}",
            "bounding_boxes": 1,
            "class_name": "garbage",
        },
    },
    "misuse": {
        "severity": "high",
        "source": "ai",
        "message": "Potential misuse detected in chute room.",
        "payload": lambda room, device: {
            "camera_id": f"CAM-{room.room_code}",
            "person_detected": True,
            "dwell_seconds": random.randint(12, 40),
        },
    },
}

AI_EVENT_TYPES = {"motion", "garbage_left", "misuse", "overflow"}


class SimulationService:
    def __init__(self) -> None:
        self.active = False
        self.task: asyncio.Task | None = None

    async def start(self) -> dict:
        if self.active:
            return {"ok": False, "message": "Simulation already running"}

        self.active = True
        self.task = asyncio.create_task(self._run())
        return {"ok": True, "message": "Simulation started"}

    async def stop(self) -> dict:
        if not self.active:
            return {"ok": False, "message": "Simulation not running"}

        self.active = False
        if self.task:
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass
            self.task = None

        return {"ok": True, "message": "Simulation stopped"}

    async def emit(
        self,
        db: AsyncSession,
        *,
        room_id: int | None = None,
        room_code: str | None = None,
        device_id: str | None = None,
        event_type: str,
        severity: str | None = None,
        source: str = "simulation",
        payload: dict | None = None,
        confidence: float | None = None,
    ) -> dict:
        room = await self._resolve_room(db, room_id=room_id, room_code=room_code)
        if not room:
            raise ValueError("Room not found")

        device = None
        if device_id:
            device = next(
                (
                    candidate
                    for candidate in room.devices
                    if candidate.device_id == device_id or str(candidate.id) == str(device_id)
                ),
                None,
            )
        elif room.devices:
            device = room.devices[0]

        result = await self._emit_room_event(
            db,
            room,
            device,
            device_identifier=device_id,
            event_type=event_type,
            severity=severity,
            source=source,
            payload=payload or {},
            confidence=confidence,
        )
        return result

    async def _run(self) -> None:
        while self.active:
            try:
                async with AsyncSessionLocal() as db:
                    rooms = (
                        await db.execute(
                            select(Room)
                            .options(selectinload(Room.devices))
                            .order_by(Room.id.asc())
                        )
                    ).scalars().all()

                    if not rooms:
                        await asyncio.sleep(3)
                        continue

                    room = random.choice(rooms)
                    device = room.devices[0] if room.devices else None
                    event_type = random.choices(
                        population=list(SIMULATION_EVENT_LIBRARY.keys()),
                        weights=[4, 2, 1, 2, 2, 1, 3, 1, 1],
                        k=1,
                    )[0]
                    await self._emit_room_event(
                        db,
                        room,
                        device,
                        event_type=event_type,
                        source="simulation",
                    )

                await asyncio.sleep(random.uniform(2.5, 6.0))
            except asyncio.CancelledError:
                raise
            except Exception:
                await asyncio.sleep(3)

    async def _resolve_room(
        self,
        db: AsyncSession,
        *,
        room_id: int | None,
        room_code: str | None,
    ) -> Room | None:
        query = select(Room).options(selectinload(Room.devices))
        if room_id is not None:
            query = query.where(Room.id == room_id)
        elif room_code:
            query = query.where(Room.room_code == room_code)
        else:
            return None
        return (await db.execute(query)).scalar_one_or_none()

    async def _emit_room_event(
        self,
        db: AsyncSession,
        room: Room,
        device: Device | None,
        *,
        device_identifier: str | None = None,
        event_type: str,
        severity: str | None = None,
        source: str = "simulation",
        payload: dict | None = None,
        confidence: float | None = None,
    ) -> dict:
        event_spec = SIMULATION_EVENT_LIBRARY.get(event_type, {})
        event_source = event_spec.get("source", "sensor")
        resolved_severity = severity or event_spec.get("severity", "medium")
        base_payload = event_spec.get("payload", lambda current_room, current_device: {})(
            room,
            device,
        )
        resolved_device_identifier = device_identifier or (device.device_id if device else None)
        event_payload = {
            **base_payload,
            **(payload or {}),
            "room_code": room.room_code,
            "room_name": room.name,
            "source": source,
            "device_id": resolved_device_identifier,
        }

        if device:
            device.last_seen_at = datetime.now(timezone.utc)
            device.status = "online"

        alert = await alert_engine.ingest_sensor_event(
            db,
            room.id,
            device.id if device else None,
            event_type,
            {
                **event_payload,
                "message": event_spec.get("message", f"{event_type.replace('_', ' ').title()} detected."),
            },
            resolved_severity,
            source="ai" if event_source == "ai" else source,
        )

        ai_event = None
        if event_type in AI_EVENT_TYPES:
            ai_event = AiEvent(
                room_id=room.id,
                camera_id=event_payload.get("camera_id", f"CAM-{room.room_code}"),
                event_type="garbage_on_floor" if event_type == "garbage_left" else event_type,
                confidence=confidence or round(random.uniform(0.74, 0.98), 2),
                snapshot_url=f"/snapshots/{room.room_code.lower()}-{event_type}.jpg",
                payload=event_payload,
            )
            db.add(ai_event)

        await db.flush()

        timestamp = datetime.now(timezone.utc).isoformat()
        telemetry_message = {
            "type": "telemetry",
            "room_id": room.id,
            "room_code": room.room_code,
            "room_name": room.name,
            "device_id": resolved_device_identifier,
            "event_type": event_type,
            "severity": resolved_severity,
            "source": source,
            "timestamp": timestamp,
            "payload": event_payload,
        }

        await broadcaster.publish("telemetry", telemetry_message)

        if ai_event:
            await broadcaster.publish(
                "telemetry",
                {
                    "type": "ai_event",
                    "id": ai_event.id,
                    "room_id": room.id,
                    "room_code": room.room_code,
                    "camera_id": ai_event.camera_id,
                    "event_type": ai_event.event_type,
                    "confidence": ai_event.confidence,
                    "snapshot_url": ai_event.snapshot_url,
                    "timestamp": ai_event.created_at.isoformat() if ai_event.created_at else timestamp,
                },
            )

        await db.commit()

        return {
            "ok": True,
            "room_id": room.id,
            "room_code": room.room_code,
            "event_type": event_type,
            "severity": resolved_severity,
            "alert_id": alert.id if alert else None,
            "ai_event_id": ai_event.id if ai_event else None,
        }


simulation_service = SimulationService()
