from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.db.session import get_db
from app.models import Building, Floor, Room, Device
from app.schemas import BuildingCreate, BuildingOut, FloorCreate, FloorOut, RoomCreate, RoomOut, DeviceCreate, DeviceOut
from app.api.deps import get_current_user
from app.services.dashboard_service import dashboard_service

router = APIRouter(tags=["registry"])

@router.get("/buildings", response_model=list[BuildingOut])
async def list_buildings(db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    return (await db.execute(select(Building).order_by(Building.id))).scalars().all()

@router.post("/buildings", response_model=BuildingOut)
async def create_building(payload: BuildingCreate, db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    obj = Building(**payload.model_dump())
    db.add(obj); await db.commit(); await db.refresh(obj); return obj

@router.get("/floors", response_model=list[FloorOut])
async def list_floors(db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    return (await db.execute(select(Floor).order_by(Floor.id))).scalars().all()

@router.post("/floors", response_model=FloorOut)
async def create_floor(payload: FloorCreate, db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    obj = Floor(**payload.model_dump())
    db.add(obj); await db.commit(); await db.refresh(obj); return obj

@router.get("/rooms", response_model=list[RoomOut])
async def list_rooms(db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    rooms = await dashboard_service.list_rooms(db)
    return [RoomOut.model_validate(room) for room in rooms]

@router.post("/rooms", response_model=RoomOut)
async def create_room(payload: RoomCreate, db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    obj = Room(**payload.model_dump())
    db.add(obj); await db.commit(); await db.refresh(obj); return obj

@router.get("/devices", response_model=list[DeviceOut])
async def list_devices(db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    return (await db.execute(select(Device).order_by(Device.id))).scalars().all()

@router.post("/devices", response_model=DeviceOut)
async def create_device(payload: DeviceCreate, db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    obj = Device(**payload.model_dump())
    db.add(obj); await db.commit(); await db.refresh(obj); return obj
