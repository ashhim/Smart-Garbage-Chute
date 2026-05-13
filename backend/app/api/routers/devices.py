from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from app.db.session import get_db
from app.models import Device, Room
from app.schemas import DeviceOut
from app.api.deps import get_current_user

router = APIRouter(prefix="/devices", tags=["devices"])

@router.get("", response_model=list[DeviceOut])
async def list_devices(
    room_id: int | None = Query(None),
    status: str | None = Query(None),
    limit: int = Query(100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
    user=Depends(get_current_user)
):
    """List all devices with optional filtering."""
    query = select(Device)
    
    if room_id:
        query = query.where(Device.room_id == room_id)
    if status:
        query = query.where(Device.status == status)
    
    query = query.order_by(desc(Device.id)).limit(limit)
    results = (await db.execute(query)).scalars().all()
    return [DeviceOut.model_validate(d) for d in results]

@router.get("/{device_id}", response_model=DeviceOut)
async def get_device(
    device_id: int,
    db: AsyncSession = Depends(get_db),
    user=Depends(get_current_user)
):
    """Get a specific device."""
    device = (await db.execute(select(Device).where(Device.id == device_id))).scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    return DeviceOut.model_validate(device)
