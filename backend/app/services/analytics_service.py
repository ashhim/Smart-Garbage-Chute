from datetime import datetime, timedelta, timezone
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import Alert, AiEvent, Building, Floor, Room, Device, OtaJob, SensorEvent

class AnalyticsService:
    async def summary(self, db: AsyncSession) -> dict:
        """Get overall system summary statistics."""
        now = datetime.now(timezone.utc)
        day_ago = now - timedelta(hours=24)
        hour_ago = now - timedelta(hours=1)
        
        counts = {}

        counts["buildings"] = (
            await db.execute(
                select(func.count(func.distinct(Building.id)))
                .select_from(Building)
                .join(Floor, Floor.building_id == Building.id)
                .join(Room, Room.floor_id == Floor.id)
            )
        ).scalar_one()

        counts["floors"] = (
            await db.execute(
                select(func.count(func.distinct(Floor.id)))
                .select_from(Floor)
                .join(Room, Room.floor_id == Floor.id)
            )
        ).scalar_one()

        counts["rooms"] = (await db.execute(select(func.count()).select_from(Room))).scalar_one()
        counts["devices"] = (await db.execute(select(func.count()).select_from(Device))).scalar_one()
        
        # Alert statistics
        counts['alerts_open'] = (await db.execute(
            select(func.count()).select_from(Alert).where(Alert.acknowledged.is_(False))
        )).scalar_one()
        
        counts['alerts_24h'] = (await db.execute(
            select(func.count()).select_from(Alert).where(Alert.created_at >= day_ago)
        )).scalar_one()
        
        counts['alerts_1h'] = (await db.execute(
            select(func.count()).select_from(Alert).where(Alert.created_at >= hour_ago)
        )).scalar_one()
        
        # AI event statistics
        counts['ai_events_24h'] = (await db.execute(
            select(func.count()).select_from(AiEvent).where(AiEvent.created_at >= day_ago)
        )).scalar_one()
        
        counts['ai_events_1h'] = (await db.execute(
            select(func.count()).select_from(AiEvent).where(AiEvent.created_at >= hour_ago)
        )).scalar_one()
        
        # OTA statistics
        counts['ota_jobs_active'] = (await db.execute(
            select(func.count()).select_from(OtaJob).where(OtaJob.status.in_(['queued', 'running']))
        )).scalar_one()
        
        counts['ota_jobs_completed_24h'] = (await db.execute(
            select(func.count()).select_from(OtaJob).where(
                OtaJob.status == 'completed',
                OtaJob.updated_at >= day_ago
            )
        )).scalar_one()
        
        # Device health
        counts['devices_online'] = (await db.execute(
            select(func.count()).select_from(Device).where(Device.status == 'online')
        )).scalar_one()
        
        counts['devices_offline'] = (await db.execute(
            select(func.count()).select_from(Device).where(Device.status == 'offline')
        )).scalar_one()
        
        return counts
    
    async def get_room_status(self, db: AsyncSession, room_id: int) -> dict:
        """Get detailed status for a specific room."""
        from app.models import Room
        
        room = await db.get(Room, room_id)
        if not room:
            return {}
        
        # Latest sensor event
        latest_sensor = (await db.execute(
            select(SensorEvent).where(SensorEvent.room_id == room_id).order_by(SensorEvent.id.desc()).limit(1)
        )).scalar_one_or_none()
        
        # Latest AI event
        latest_ai = (await db.execute(
            select(AiEvent).where(AiEvent.room_id == room_id).order_by(AiEvent.id.desc()).limit(1)
        )).scalar_one_or_none()
        
        # Open alerts
        open_alerts = (await db.execute(
            select(func.count()).select_from(Alert).where(
                Alert.room_id == room_id,
                Alert.acknowledged.is_(False)
            )
        )).scalar_one()
        
        return {
            "room_id": room_id,
            "room_code": room.room_code,
            "latest_sensor_event": {
                "type": latest_sensor.event_type if latest_sensor else None,
                "timestamp": latest_sensor.created_at.isoformat() if latest_sensor else None,
                "payload": latest_sensor.payload if latest_sensor else {}
            },
            "latest_ai_event": {
                "type": latest_ai.event_type if latest_ai else None,
                "timestamp": latest_ai.created_at.isoformat() if latest_ai else None,
                "confidence": latest_ai.confidence if latest_ai else None
            },
            "open_alerts_count": open_alerts
        }
    
    async def get_alert_statistics(self, db: AsyncSession, hours: int = 24) -> dict:
        """Get alert statistics for the specified time period."""
        since = datetime.now(timezone.utc) - timedelta(hours=hours)
        
        # Alerts by category
        results = (await db.execute(
            select(Alert.category, func.count()).select_from(Alert)
            .where(Alert.created_at >= since)
            .group_by(Alert.category)
        )).all()
        
        alerts_by_category = {row[0]: row[1] for row in results}
        
        # Alerts by severity
        results = (await db.execute(
            select(Alert.severity, func.count()).select_from(Alert)
            .where(Alert.created_at >= since)
            .group_by(Alert.severity)
        )).all()
        
        alerts_by_severity = {row[0]: row[1] for row in results}
        
        return {
            "time_period_hours": hours,
            "by_category": alerts_by_category,
            "by_severity": alerts_by_severity,
            "total": sum(alerts_by_category.values())
        }

analytics_service = AnalyticsService()
