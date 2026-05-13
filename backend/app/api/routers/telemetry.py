from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from app.db.session import get_db
from app.models import SensorEvent, AiEvent, MaintenanceLog
from app.schemas import SensorEventOut, AiEventOut, MaintenanceLogOut
from app.api.deps import get_current_user

router = APIRouter(tags=["telemetry"])

@router.get("/events", response_model=dict)
async def list_events(
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    user=Depends(get_current_user)
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
    user=Depends(get_current_user)
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
    user=Depends(get_current_user)
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

@router.get("/maintenance", response_model=list[MaintenanceLogOut])
async def list_maintenance(
    room_id: int | None = Query(None),
    status: str | None = Query(None),
    limit: int = Query(100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
    user=Depends(get_current_user)
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
