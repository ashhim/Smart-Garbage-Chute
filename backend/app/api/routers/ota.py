from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.db.session import get_db
from app.models import OtaJob, FirmwareVersion
from app.schemas import OtaJobCreate, OtaJobOut
from app.api.deps import get_current_user
from app.services.ota_service import ota_service

router = APIRouter(prefix="/ota", tags=["ota"])

@router.get("/jobs", response_model=list[OtaJobOut])
async def list_jobs(db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    return (await db.execute(select(OtaJob).order_by(OtaJob.id.desc()))).scalars().all()

@router.post("/jobs", response_model=OtaJobOut)
async def create_job(payload: OtaJobCreate, db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    job = await ota_service.create_job(db, payload.target_type, payload.target_ref, payload.firmware_version, payload.requested_by)
    await db.commit(); await db.refresh(job); return job
