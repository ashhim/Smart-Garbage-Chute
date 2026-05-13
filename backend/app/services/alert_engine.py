from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models import Alert, SensorEvent, Room, Device
from app.services.broadcaster import broadcaster
import logging

logger = logging.getLogger(__name__)

class AlertEngine:
    async def ingest_sensor_event(self, db: AsyncSession, room_id: int, device_id: int | None, event_type: str, payload: dict, severity: str = "medium") -> Alert | None:
        """Ingest sensor event and create alert if needed."""
        event = SensorEvent(room_id=room_id, device_id=device_id, event_type=event_type, payload=payload, severity=severity)
        db.add(event)
        alert = None
        
        if event_type in {"blockage", "door_prolonged_open", "leak", "overflow", "misuse", "ai_misuse"}:
            # Get room code for logging
            room = await db.get(Room, room_id)
            room_code = room.room_code if room else "UNKNOWN"
            
            message = payload.get("message") or f"{event_type.replace('_', ' ').title()} detected"
            alert = Alert(
                room_id=room_id,
                source="sensor" if event_type != "ai_misuse" else "ai",
                category=event_type,
                message=message,
                severity=severity
            )
            db.add(alert)
            await db.flush()
            
            # Broadcast to WebSocket subscribers
            await broadcaster.publish("alerts", {
                "type": "alert.created",
                "alert_id": alert.id,
                "room_id": room_id,
                "room_code": room_code,
                "category": event_type,
                "message": message,
                "severity": severity
            })
            
            logger.info("alert.created", extra={
                "alert_id": alert.id,
                "room_code": room_code,
                "category": event_type,
                "severity": severity
            })
            
            # Send notifications through multiple channels
            try:
                from app.services.notification_service import notification_service
                await notification_service.send_alert_notification(
                    db,
                    alert.id,
                    room_code,
                    event_type,
                    severity,
                    message
                )
            except Exception as exc:
                logger.exception("alert.notification_failed", exc_info=exc)
        
        return alert

    async def acknowledge(self, db: AsyncSession, alert_id: int, actor: str) -> Alert | None:
        """Acknowledge an alert."""
        alert = await db.get(Alert, alert_id)
        if not alert:
            return None
        alert.acknowledged = True
        alert.acknowledged_by = actor
        alert.acknowledged_at = datetime.now(timezone.utc)
        
        await broadcaster.publish("alerts", {
            "type": "alert.acknowledged",
            "alert_id": alert_id,
            "actor": actor
        })
        
        logger.info("alert.acknowledged", extra={"alert_id": alert_id, "actor": actor})
        
        return alert

alert_engine = AlertEngine()
