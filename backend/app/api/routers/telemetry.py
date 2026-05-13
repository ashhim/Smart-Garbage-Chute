from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload
from app.db.session import get_db
from app.core.rbac import MONITORING_ROLES
from app.models import SensorEvent, AiEvent, MaintenanceLog, Room
from app.models import User
from app.schemas import SensorEventOut, AiEventOut, MaintenanceLogOut, AiEventCreate
from app.api.deps import require_roles
from app.services.alert_engine import alert_engine
from app.services.broadcaster import broadcaster

router = APIRouter(tags=["telemetry"])

@router.get("/events", response_model=dict)
async def list_events(
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    """List recent sensor and AI events."""
    sensor = (await db.execute(
        select(SensorEvent)
        .order_by(desc(SensorEvent.id))
        .limit(limit)
        .offset(offset)
    )).scalars().all()
    
    ai = (await db.execute(
        select(AiEvent)
        .order_by(desc(AiEvent.id))
        .limit(limit)
        .offset(offset)
    )).scalars().all()
    
    return {
        "sensor_events": [SensorEventOut.model_validate(e) for e in sensor],
        "ai_events": [AiEventOut.model_validate(e) for e in ai],
    }

@router.get("/sensor-events", response_model=list[SensorEventOut])
async def list_sensor_events(
    room_id: int | None = Query(None),
    event_type: str | None = Query(None),
    limit: int = Query(100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    """List sensor events with optional filtering."""
    query = select(SensorEvent).order_by(desc(SensorEvent.id))
    
    if room_id:
        query = query.where(SensorEvent.room_id == room_id)
    if event_type:
        query = query.where(SensorEvent.event_type == event_type)
    
    query = query.limit(limit)
    results = (await db.execute(query)).scalars().all()
    return [SensorEventOut.model_validate(e) for e in results]

@router.get("/ai-events", response_model=list[AiEventOut])
async def list_ai_events(
    room_id: int | None = Query(None),
    event_type: str | None = Query(None),
    limit: int = Query(100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    """List AI detection events with optional filtering."""
    query = select(AiEvent).order_by(desc(AiEvent.id))
    
    if room_id:
        query = query.where(AiEvent.room_id == room_id)
    if event_type:
        query = query.where(AiEvent.event_type == event_type)
    
    query = query.limit(limit)
    results = (await db.execute(query)).scalars().all()
    return [AiEventOut.model_validate(e) for e in results]

@router.post("/ai-events", response_model=AiEventOut, status_code=201)
async def create_ai_event(payload: AiEventCreate, db: AsyncSession = Depends(get_db)):
    """Ingest AI detection events from the AI service or simulator."""
    room_reference = payload.room_id
    room_query = select(Room)
    if payload.room_code:
        room_query = room_query.where(Room.room_code == payload.room_code)
    elif isinstance(room_reference, int):
        room_query = room_query.where(Room.id == room_reference)
    elif isinstance(room_reference, str) and room_reference.isdigit():
        room_query = room_query.where(Room.id == int(room_reference))
    elif isinstance(room_reference, str):
        room_query = room_query.where(Room.room_code == room_reference)
    else:
        raise HTTPException(status_code=422, detail="room_id or room_code is required")

    room = (await db.execute(room_query.options(selectinload(Room.devices)))).scalar_one_or_none()
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")

    device = room.devices[0] if room.devices else None
    event_payload = {
        **payload.payload,
        "room_code": room.room_code,
        "camera_id": payload.camera_id,
        "source": "ai_service",
    }

    await alert_engine.ingest_sensor_event(
        db,
        room.id,
        device.id if device else None,
        payload.event_type,
        {
            **event_payload,
            "message": payload.payload.get("message")
            or f"{payload.event_type.replace('_', ' ').title()} detected by AI camera.",
        },
        "high" if payload.event_type in {"misuse", "overflow", "leak", "garbage_on_floor"} else "info",
        source="ai",
    )

    ai_event = AiEvent(
        room_id=room.id,
        camera_id=payload.camera_id,
        event_type=payload.event_type,
        confidence=payload.confidence,
        snapshot_url=payload.snapshot_url,
        payload=event_payload,
    )
    db.add(ai_event)
    await db.flush()

    await broadcaster.publish(
        "telemetry",
        {
            "type": "ai_event",
            "id": ai_event.id,
            "room_id": room.id,
            "room_code": room.room_code,
            "camera_id": payload.camera_id,
            "event_type": payload.event_type,
            "confidence": payload.confidence,
            "snapshot_url": payload.snapshot_url,
            "timestamp": ai_event.created_at.isoformat() if ai_event.created_at else datetime.now(timezone.utc).isoformat(),
        },
    )

    await db.commit()
    await db.refresh(ai_event)
    return AiEventOut.model_validate(ai_event)

@router.get("/maintenance", response_model=list[MaintenanceLogOut])
async def list_maintenance(
    room_id: int | None = Query(None),
    status: str | None = Query(None),
    limit: int = Query(100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    """List maintenance logs with optional filtering."""
    query = select(MaintenanceLog).order_by(desc(MaintenanceLog.id))
    
    if room_id:
        query = query.where(MaintenanceLog.room_id == room_id)
    if status:
        query = query.where(MaintenanceLog.status == status)
    
    query = query.limit(limit)
    results = (await db.execute(query)).scalars().all()
    return [MaintenanceLogOut.model_validate(m) for m in results]
