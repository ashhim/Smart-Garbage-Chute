from __future__ import annotations

from collections import defaultdict
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import AiEvent, Alert, Device, Floor, Room, SensorEvent


class DashboardService:
    async def list_devices(
        self,
        db: AsyncSession,
        room_id: int | None = None,
        status: str | None = None,
        limit: int = 100,
    ) -> list[dict]:
        query = (
            select(Device)
            .options(
                selectinload(Device.room)
                .selectinload(Room.floor)
                .selectinload(Floor.building)
            )
            .order_by(Device.id.desc())
            .limit(limit)
        )

        if room_id:
            query = query.where(Device.room_id == room_id)
        if status:
            query = query.where(Device.status == status)

        devices = (await db.execute(query)).scalars().all()
        room_ids = [device.room_id for device in devices]
        alert_counts = await self._get_open_alert_counts(db, room_ids)
        latest_sensor = await self._get_latest_sensor_events(db, room_ids)
        latest_ai = await self._get_latest_ai_events(db, room_ids)

        payload: list[dict] = []
        for device in devices:
            room = device.room
            floor = room.floor if room else None
            building = floor.building if floor else None
            latest_sensor_event = latest_sensor.get(device.room_id)
            latest_ai_event = latest_ai.get(device.room_id)
            last_event = self._pick_latest(latest_sensor_event, latest_ai_event)

            payload.append(
                {
                    "id": device.id,
                    "room_id": device.room_id,
                    "device_id": device.device_id,
                    "device_type": device.device_type,
                    "firmware_version": device.firmware_version,
                    "status": device.status,
                    "last_seen_at": device.last_seen_at,
                    "room_code": room.room_code if room else None,
                    "room_name": room.name if room else None,
                    "zone": room.zone if room else None,
                    "floor_level": floor.level if floor else None,
                    "building_code": building.code if building else None,
                    "building_name": building.name if building else None,
                    "open_alert_count": alert_counts.get(device.room_id, 0),
                    "last_event_type": getattr(last_event, "event_type", None),
                    "last_event_at": getattr(last_event, "created_at", None),
                }
            )

        return payload

    async def list_rooms(self, db: AsyncSession) -> list[dict]:
        rooms = (
            await db.execute(
                select(Room)
                .options(
                    selectinload(Room.floor)
                    .selectinload(Floor.building),
                    selectinload(Room.devices),
                )
                .order_by(Room.id.asc())
            )
        ).scalars().all()

        room_ids = [room.id for room in rooms]
        alert_counts = await self._get_open_alert_counts(db, room_ids)
        latest_sensor = await self._get_latest_sensor_events(db, room_ids)
        latest_ai = await self._get_latest_ai_events(db, room_ids)

        payload: list[dict] = []
        for room in rooms:
            devices = list(room.devices)
            online_devices = sum(1 for device in devices if str(device.status).lower() == "online")
            primary_device = devices[0] if devices else None
            latest_sensor_event = latest_sensor.get(room.id)
            latest_ai_event = latest_ai.get(room.id)
            last_event = self._pick_latest(latest_sensor_event, latest_ai_event)
            open_alert_count = alert_counts.get(room.id, 0)

            payload.append(
                {
                    "id": room.id,
                    "floor_id": room.floor_id,
                    "room_code": room.room_code,
                    "name": room.name,
                    "zone": room.zone,
                    "building_code": room.floor.building.code if room.floor and room.floor.building else None,
                    "building_name": room.floor.building.name if room.floor and room.floor.building else None,
                    "floor_level": room.floor.level if room.floor else None,
                    "devices_count": len(devices),
                    "online_devices": online_devices,
                    "open_alert_count": open_alert_count,
                    "primary_device_id": primary_device.device_id if primary_device else None,
                    "primary_device_status": primary_device.status if primary_device else None,
                    "last_event_type": getattr(last_event, "event_type", None),
                    "last_event_at": getattr(last_event, "created_at", None),
                    "status": self._derive_room_status(
                        devices=devices,
                        open_alert_count=open_alert_count,
                        last_event=last_event,
                    ),
                }
            )

        return payload

    async def list_alerts(self, db: AsyncSession) -> list[dict]:
        alerts = (
            await db.execute(
                select(Alert)
                .options(
                    selectinload(Alert.room)
                    .selectinload(Room.floor)
                    .selectinload(Floor.building)
                )
                .order_by(Alert.id.desc())
            )
        ).scalars().all()

        room_primary_devices = await self._get_primary_device_ids(db)
        payload: list[dict] = []
        for alert in alerts:
            room = alert.room
            floor = room.floor if room else None
            building = floor.building if floor else None
            payload.append(
                {
                    "id": alert.id,
                    "room_id": alert.room_id,
                    "source": alert.source,
                    "category": alert.category,
                    "message": alert.message,
                    "severity": alert.severity,
                    "acknowledged": alert.acknowledged,
                    "acknowledged_by": alert.acknowledged_by,
                    "acknowledged_at": alert.acknowledged_at,
                    "created_at": alert.created_at,
                    "room_code": room.room_code if room else None,
                    "room_name": room.name if room else None,
                    "building_code": building.code if building else None,
                    "building_name": building.name if building else None,
                    "device_id": room_primary_devices.get(alert.room_id),
                }
            )

        return payload

    async def _get_open_alert_counts(
        self,
        db: AsyncSession,
        room_ids: list[int],
    ) -> dict[int, int]:
        if not room_ids:
            return {}

        results = (
            await db.execute(
                select(Alert.room_id, func.count(Alert.id))
                .where(
                    Alert.room_id.in_(room_ids),
                    Alert.acknowledged.is_(False),
                )
                .group_by(Alert.room_id)
            )
        ).all()
        return {room_id: count for room_id, count in results}

    async def _get_latest_sensor_events(
        self,
        db: AsyncSession,
        room_ids: list[int],
    ) -> dict[int, SensorEvent]:
        if not room_ids:
            return {}

        latest_ids = (
            select(
                SensorEvent.room_id.label("room_id"),
                func.max(SensorEvent.id).label("event_id"),
            )
            .where(SensorEvent.room_id.in_(room_ids))
            .group_by(SensorEvent.room_id)
            .subquery()
        )

        events = (
            await db.execute(
                select(SensorEvent).join(latest_ids, SensorEvent.id == latest_ids.c.event_id)
            )
        ).scalars().all()
        return {event.room_id: event for event in events}

    async def _get_latest_ai_events(
        self,
        db: AsyncSession,
        room_ids: list[int],
    ) -> dict[int, AiEvent]:
        if not room_ids:
            return {}

        latest_ids = (
            select(
                AiEvent.room_id.label("room_id"),
                func.max(AiEvent.id).label("event_id"),
            )
            .where(AiEvent.room_id.in_(room_ids))
            .group_by(AiEvent.room_id)
            .subquery()
        )

        events = (
            await db.execute(
                select(AiEvent).join(latest_ids, AiEvent.id == latest_ids.c.event_id)
            )
        ).scalars().all()
        return {event.room_id: event for event in events}

    async def _get_primary_device_ids(self, db: AsyncSession) -> dict[int, str]:
        devices = (
            await db.execute(select(Device).order_by(Device.room_id.asc(), Device.id.asc()))
        ).scalars().all()
        mapping: dict[int, str] = {}
        for device in devices:
            mapping.setdefault(device.room_id, device.device_id)
        return mapping

    def _pick_latest(self, sensor_event: SensorEvent | None, ai_event: AiEvent | None):
        if sensor_event and ai_event:
            return sensor_event if sensor_event.created_at >= ai_event.created_at else ai_event
        return sensor_event or ai_event

    def _derive_room_status(
        self,
        *,
        devices: list[Device],
        open_alert_count: int,
        last_event: SensorEvent | AiEvent | None,
    ) -> str:
        if open_alert_count > 0:
            return "attention"
        if not devices:
            return "unassigned"
        if all(str(device.status).lower() != "online" for device in devices):
            return "offline"
        if last_event and getattr(last_event, "event_type", None) in {"overflow", "motion"}:
            return "active"
        return "normal"


dashboard_service = DashboardService()
