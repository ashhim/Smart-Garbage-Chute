import logging
from enum import Enum
from datetime import datetime, timezone
from abc import ABC, abstractmethod
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import Notification
from app.services.broadcaster import broadcaster

logger = logging.getLogger(__name__)

class NotificationChannel(str, Enum):
    """Supported notification channels."""
    EMAIL = "email"
    SMS = "sms"
    WHATSAPP = "whatsapp"
    PUSH = "push"
    BMS = "bms"
    CONTROL_ROOM = "control_room"

class BaseNotificationAdapter(ABC):
    """Base class for notification adapters."""
    
    @abstractmethod
    async def send(self, recipient: str, title: str, body: str, meta: dict = None) -> bool:
        """Send notification via specific channel. Returns True on success."""
        pass

class EmailAdapter(BaseNotificationAdapter):
    """Email notification adapter (stub)."""
    
    async def send(self, recipient: str, title: str, body: str, meta: dict = None) -> bool:
        logger.info("email.send", extra={"recipient": recipient, "title": title})
        # TODO: Integrate with actual SMTP service (SendGrid, AWS SES, etc.)
        return True

class SmsAdapter(BaseNotificationAdapter):
    """SMS notification adapter (stub)."""
    
    async def send(self, recipient: str, title: str, body: str, meta: dict = None) -> bool:
        logger.info("sms.send", extra={"recipient": recipient, "title": title})
        # TODO: Integrate with actual SMS service (Twilio, AWS SNS, etc.)
        return True

class WhatsAppAdapter(BaseNotificationAdapter):
    """WhatsApp notification adapter (stub)."""
    
    async def send(self, recipient: str, title: str, body: str, meta: dict = None) -> bool:
        logger.info("whatsapp.send", extra={"recipient": recipient, "title": title})
        # TODO: Integrate with actual WhatsApp service (Twilio, MessageBird, etc.)
        return True

class PushAdapter(BaseNotificationAdapter):
    """Push notification adapter (stub)."""
    
    async def send(self, recipient: str, title: str, body: str, meta: dict = None) -> bool:
        logger.info("push.send", extra={"recipient": recipient, "title": title})
        # TODO: Integrate with Firebase Cloud Messaging or similar
        return True

class BmsAdapter(BaseNotificationAdapter):
    """BMS (Building Management System) integration adapter (stub)."""
    
    async def send(self, recipient: str, title: str, body: str, meta: dict = None) -> bool:
        logger.info("bms.send", extra={"recipient": recipient, "title": title})
        # TODO: Integrate with actual BMS HTTP/MQTT API
        return True

class ControlRoomAdapter(BaseNotificationAdapter):
    """Control room WebSocket broadcast adapter."""
    
    async def send(self, recipient: str, title: str, body: str, meta: dict = None) -> bool:
        logger.info("control_room.send", extra={"title": title})
        payload = meta or {}
        # Broadcast to all connected WebSocket clients
        await broadcaster.publish("alerts", {
            "type": "notification",
            "title": title,
            "body": body,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            **payload,
        })
        return True

class NotificationService:
    """Central notification service managing all channels."""
    
    def __init__(self):
        self.adapters = {
            NotificationChannel.EMAIL: EmailAdapter(),
            NotificationChannel.SMS: SmsAdapter(),
            NotificationChannel.WHATSAPP: WhatsAppAdapter(),
            NotificationChannel.PUSH: PushAdapter(),
            NotificationChannel.BMS: BmsAdapter(),
            NotificationChannel.CONTROL_ROOM: ControlRoomAdapter(),
        }
    
    async def send(
        self,
        db: AsyncSession,
        channel: str | NotificationChannel,
        recipient: str,
        title: str,
        body: str,
        meta: dict = None
    ) -> Notification | None:
        """Send notification via specified channel and record in database."""
        try:
            if isinstance(channel, str):
                channel = NotificationChannel(channel)
            
            meta = meta or {}
            
            # Create database record
            notification = Notification(
                channel=channel.value,
                recipient=recipient,
                title=title,
                body=body,
                status="queued",
                meta=meta
            )
            db.add(notification)
            await db.flush()
            
            # Send via adapter
            adapter = self.adapters.get(channel)
            if not adapter:
                logger.warning("notification.adapter_not_found", extra={"channel": channel.value})
                notification.status = "failed"
                await db.commit()
                return notification
            
            success = await adapter.send(recipient, title, body, meta)
            notification.status = "sent" if success else "failed"
            await db.commit()
            
            logger.info("notification.sent", extra={
                "channel": channel.value,
                "recipient": recipient,
                "id": notification.id
            })
            
            return notification
        except Exception as exc:
            logger.exception("notification.send_failed", exc_info=exc)
            return None
    
    async def send_alert_notification(
        self,
        db: AsyncSession,
        alert_id: int,
        room_code: str,
        alert_category: str,
        severity: str,
        message: str,
        channels: list[str] = None
    ) -> None:
        """Send alert notification through multiple channels."""
        if channels is None:
            # Default channels based on severity
            if severity == "critical":
                channels = [
                    NotificationChannel.CONTROL_ROOM.value,
                    NotificationChannel.WHATSAPP.value,
                    NotificationChannel.SMS.value,
                    NotificationChannel.EMAIL.value,
                    NotificationChannel.BMS.value,
                ]
            elif severity == "high":
                channels = [
                    NotificationChannel.CONTROL_ROOM.value,
                    NotificationChannel.WHATSAPP.value,
                    NotificationChannel.SMS.value,
                    NotificationChannel.EMAIL.value,
                ]
            elif severity == "medium":
                channels = [
                    NotificationChannel.CONTROL_ROOM.value,
                    NotificationChannel.EMAIL.value,
                ]
            else:
                channels = [NotificationChannel.CONTROL_ROOM.value]
        
        title = f"[{severity.upper()}] {room_code}: {alert_category.replace('_', ' ').title()}"
        
        for channel in channels:
            try:
                await self.send(
                    db,
                    channel,
                    recipient=f"alert_{alert_id}",  # Placeholder
                    title=title,
                    body=message,
                    meta={
                        "alert_id": alert_id,
                        "room_code": room_code,
                        "category": alert_category,
                        "severity": severity
                    }
                )
            except Exception as exc:
                logger.exception(f"notification.send_failed.{channel}", exc_info=exc)

notification_service = NotificationService()
