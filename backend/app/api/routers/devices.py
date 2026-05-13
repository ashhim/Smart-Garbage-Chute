from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.db.session import get_db
from app.core.rbac import MONITORING_ROLES
from app.models import Device
from app.schemas import DeviceOut
from app.api.deps import require_roles
from app.models import User
from app.services.dashboard_service import dashboard_service

router = APIRouter(prefix="/devices", tags=["devices"])

@router.get("", response_model=list[DeviceOut])
async def list_devices(
    room_id: int | None = Query(None),
    status: str | None = Query(None),
    limit: int = Query(100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    """List all devices with optional filtering."""
    results = await dashboard_service.list_devices(
        db,
        room_id=room_id,
        status=status,
        limit=limit,
    )
    return [DeviceOut.model_validate(device) for device in results]

@router.get("/{device_id}", response_model=DeviceOut)
async def get_device(
    device_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    """Get a specific device."""
    device = (await db.execute(select(Device).where(Device.id == device_id))).scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    return DeviceOut.model_validate(device)
