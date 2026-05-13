from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_roles
from app.core.rbac import FACILITY_MANAGEMENT_ROLES, MONITORING_ROLES
from app.db.session import get_db
from app.models import Building, Device, Floor, Room, User
from app.schemas import (
    BuildingCreate,
    BuildingOut,
    BuildingUpdate,
    DeviceCreate,
    DeviceOut,
    DeviceUpdate,
    FloorCreate,
    FloorOut,
    FloorUpdate,
    RoomCreate,
    RoomOut,
    RoomUpdate,
)
from app.services.audit_service import audit_service
from app.services.dashboard_service import dashboard_service

router = APIRouter(tags=["registry"])


@router.get("/buildings", response_model=list[BuildingOut])
async def list_buildings(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    return (await db.execute(select(Building).order_by(Building.id))).scalars().all()


@router.post("/buildings", response_model=BuildingOut, status_code=201)
async def create_building(
    payload: BuildingCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = Building(**payload.model_dump())
    db.add(obj)
    await db.flush()
    await audit_service.log(
        db,
        actor=user.email,
        action="building.create",
        entity_type="building",
        entity_id=str(obj.id),
        payload=payload.model_dump(),
    )
    await db.commit()
    await db.refresh(obj)
    return obj


@router.patch("/buildings/{building_id}", response_model=BuildingOut)
async def update_building(
    building_id: int,
    payload: BuildingUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = await db.get(Building, building_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Building not found")

    changes = payload.model_dump(exclude_none=True)
    for field, value in changes.items():
        setattr(obj, field, value)

    await audit_service.log(
        db,
        actor=user.email,
        action="building.update",
        entity_type="building",
        entity_id=str(building_id),
        payload=changes,
    )
    await db.commit()
    await db.refresh(obj)
    return obj


@router.delete("/buildings/{building_id}", status_code=204)
async def delete_building(
    building_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = await db.get(Building, building_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Building not found")

    await audit_service.log(
        db,
        actor=user.email,
        action="building.delete",
        entity_type="building",
        entity_id=str(building_id),
        payload={"code": obj.code, "name": obj.name},
    )
    await db.delete(obj)
    await db.commit()


@router.get("/floors", response_model=list[FloorOut])
async def list_floors(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    return (await db.execute(select(Floor).order_by(Floor.id))).scalars().all()


@router.post("/floors", response_model=FloorOut, status_code=201)
async def create_floor(
    payload: FloorCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = Floor(**payload.model_dump())
    db.add(obj)
    await db.flush()
    await audit_service.log(
        db,
        actor=user.email,
        action="floor.create",
        entity_type="floor",
        entity_id=str(obj.id),
        payload=payload.model_dump(),
    )
    await db.commit()
    await db.refresh(obj)
    return obj


@router.patch("/floors/{floor_id}", response_model=FloorOut)
async def update_floor(
    floor_id: int,
    payload: FloorUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = await db.get(Floor, floor_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Floor not found")

    changes = payload.model_dump(exclude_none=True)
    for field, value in changes.items():
        setattr(obj, field, value)

    await audit_service.log(
        db,
        actor=user.email,
        action="floor.update",
        entity_type="floor",
        entity_id=str(floor_id),
        payload=changes,
    )
    await db.commit()
    await db.refresh(obj)
    return obj


@router.delete("/floors/{floor_id}", status_code=204)
async def delete_floor(
    floor_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = await db.get(Floor, floor_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Floor not found")

    await audit_service.log(
        db,
        actor=user.email,
        action="floor.delete",
        entity_type="floor",
        entity_id=str(floor_id),
        payload={"name": obj.name, "level": obj.level},
    )
    await db.delete(obj)
    await db.commit()


@router.get("/rooms", response_model=list[RoomOut])
async def list_rooms(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    rooms = await dashboard_service.list_rooms(db)
    return [RoomOut.model_validate(room) for room in rooms]


@router.post("/rooms", response_model=RoomOut, status_code=201)
async def create_room(
    payload: RoomCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = Room(**payload.model_dump())
    db.add(obj)
    await db.flush()
    await audit_service.log(
        db,
        actor=user.email,
        action="room.create",
        entity_type="room",
        entity_id=str(obj.id),
        payload=payload.model_dump(),
    )
    await db.commit()
    rooms = await dashboard_service.list_rooms(db)
    room = next((candidate for candidate in rooms if candidate["id"] == obj.id), None)
    if not room:
        raise HTTPException(status_code=500, detail="Room created but could not be loaded")
    return RoomOut.model_validate(room)


@router.patch("/rooms/{room_id}", response_model=RoomOut)
async def update_room(
    room_id: int,
    payload: RoomUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = await db.get(Room, room_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Room not found")

    changes = payload.model_dump(exclude_none=True)
    for field, value in changes.items():
        setattr(obj, field, value)

    await audit_service.log(
        db,
        actor=user.email,
        action="room.update",
        entity_type="room",
        entity_id=str(room_id),
        payload=changes,
    )
    await db.commit()
    rooms = await dashboard_service.list_rooms(db)
    room = next((candidate for candidate in rooms if candidate["id"] == room_id), None)
    if not room:
        raise HTTPException(status_code=500, detail="Room updated but could not be loaded")
    return RoomOut.model_validate(room)


@router.delete("/rooms/{room_id}", status_code=204)
async def delete_room(
    room_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = await db.get(Room, room_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Room not found")

    await audit_service.log(
        db,
        actor=user.email,
        action="room.delete",
        entity_type="room",
        entity_id=str(room_id),
        payload={"room_code": obj.room_code, "name": obj.name},
    )
    await db.delete(obj)
    await db.commit()


@router.post("/devices", response_model=DeviceOut, status_code=201)
async def create_device(
    payload: DeviceCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = Device(**payload.model_dump())
    db.add(obj)
    await db.flush()
    await audit_service.log(
        db,
        actor=user.email,
        action="device.create",
        entity_type="device",
        entity_id=str(obj.id),
        payload=payload.model_dump(),
    )
    await db.commit()
    devices = await dashboard_service.list_devices(db, room_id=obj.room_id, limit=1000)
    device = next((candidate for candidate in devices if candidate["id"] == obj.id), None)
    if not device:
        raise HTTPException(status_code=500, detail="Device created but could not be loaded")
    return DeviceOut.model_validate(device)


@router.patch("/devices/{device_id}", response_model=DeviceOut)
async def update_device(
    device_id: int,
    payload: DeviceUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = await db.get(Device, device_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Device not found")

    changes = payload.model_dump(exclude_none=True)
    for field, value in changes.items():
        setattr(obj, field, value)

    await audit_service.log(
        db,
        actor=user.email,
        action="device.update",
        entity_type="device",
        entity_id=str(device_id),
        payload=changes,
    )
    await db.commit()
    devices = await dashboard_service.list_devices(db, room_id=obj.room_id, limit=1000)
    device = next((candidate for candidate in devices if candidate["id"] == device_id), None)
    if not device:
        raise HTTPException(status_code=500, detail="Device updated but could not be loaded")
    return DeviceOut.model_validate(device)


@router.delete("/devices/{device_id}", status_code=204)
async def delete_device(
    device_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    obj = await db.get(Device, device_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Device not found")

    await audit_service.log(
        db,
        actor=user.email,
        action="device.delete",
        entity_type="device",
        entity_id=str(device_id),
        payload={"device_id": obj.device_id, "room_id": obj.room_id},
    )
    await db.delete(obj)
    await db.commit()
