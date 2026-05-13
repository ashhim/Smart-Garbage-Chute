from __future__ import annotations
import asyncio
import json
import logging
from urllib.parse import urlparse

import paho.mqtt.client as mqtt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.services.alert_engine import alert_engine
from app.services.broadcaster import broadcaster
from app.models import Device, Room, SensorEvent
from app.db.session import AsyncSessionLocal

logger = logging.getLogger(__name__)
settings = get_settings()

class MqttService:
    def __init__(self):
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        self.connected = False

    def start(self):
        if not settings.mqtt_host:
            return
        try:
            self.client.on_connect = self._on_connect
            self.client.on_message = self._on_message
            self.client.connect(settings.mqtt_host, settings.mqtt_port, 60)
            self.client.loop_start()
        except Exception as exc:
            logger.warning("mqtt.start.failed", exc_info=exc)

    def _on_connect(self, client, userdata, flags, reason_code, properties=None):
        logger.info("mqtt.connected", extra={"reason_code": str(reason_code)})
        client.subscribe("garbage/#")
        self.connected = True

    def _on_message(self, client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode())
            logger.info("mqtt.message", extra={"topic": msg.topic, "payload": payload})
            
            # Parse topic: garbage/telemetry/{room_code}
            topic_parts = msg.topic.split("/")
            if len(topic_parts) >= 3 and topic_parts[1] == "telemetry":
                room_code = topic_parts[2]
                asyncio.create_task(self._process_telemetry(room_code, payload))
        except Exception:
            logger.exception("mqtt.message.parse_failed")

    async def _process_telemetry(self, room_code: str, payload: dict):
        """Ingest MQTT telemetry message into database."""
        try:
            async with AsyncSessionLocal() as db:
                # Find room by room_code
                room = (await db.execute(select(Room).where(Room.room_code == room_code))).scalar_one_or_none()
                if not room:
                    logger.warning("mqtt.telemetry.room_not_found", extra={"room_code": room_code})
                    return
                
                # Find device by room_id or create generic entry
                device = (await db.execute(select(Device).where(Device.room_id == room.id).limit(1))).scalar_one_or_none()
                device_id = device.id if device else None
                
                # Determine event type based on payload
                event_type = "heartbeat"
                severity = "info"
                
                if payload.get("blockage"):
                    event_type = "blockage"
                    severity = "high"
                elif payload.get("leak_detected"):
                    event_type = "leak"
                    severity = "high"
                elif payload.get("door_open"):
                    event_type = "door_open"
                    severity = "medium"
                elif payload.get("motion_detected"):
                    event_type = "motion"
                    severity = "info"
                
                # Create sensor event
                event = SensorEvent(
                    room_id=room.id,
                    device_id=device_id,
                    event_type=event_type,
                    payload=payload,
                    severity=severity
                )
                db.add(event)
                
                # Update device last_seen_at timestamp
                if device:
                    from datetime import datetime, timezone
                    device.last_seen_at = datetime.now(timezone.utc)
                
                await db.commit()
                
                # Generate alert if needed
                if severity != "info":
                    await alert_engine.ingest_sensor_event(
                        db, room.id, device_id, event_type, payload, severity
                    )
                    await db.commit()
                
                # Broadcast to WebSocket subscribers
                await broadcaster.publish("telemetry", {
                    "type": "telemetry",
                    "room_code": room_code,
                    "event_type": event_type,
                    "payload": payload,
                    "severity": severity
                })
                
                logger.info("mqtt.telemetry.processed", extra={
                    "room_code": room_code,
                    "event_type": event_type,
                    "severity": severity
                })
        except Exception as exc:
            logger.exception("mqtt.telemetry.processing_failed", exc_info=exc)

mqtt_service = MqttService()
