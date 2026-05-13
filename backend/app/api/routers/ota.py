from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.db.session import get_db
from app.core.rbac import FACILITY_MANAGEMENT_ROLES, MONITORING_ROLES
from app.models import User
from app.models import OtaJob, FirmwareVersion
from app.schemas import OtaJobCreate, OtaJobOut
from app.api.deps import require_roles
from app.services.audit_service import audit_service
from app.services.ota_service import ota_service

router = APIRouter(prefix="/ota", tags=["ota"])

@router.get("/jobs", response_model=list[OtaJobOut])
async def list_jobs(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    return (await db.execute(select(OtaJob).order_by(OtaJob.id.desc()))).scalars().all()

@router.post("/jobs", response_model=OtaJobOut)
async def create_job(
    payload: OtaJobCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    job = await ota_service.create_job(
        db,
        payload.target_type,
        payload.target_ref,
        payload.firmware_version,
        payload.requested_by or user.email,
    )
    await audit_service.log(
        db,
        actor=user.email,
        action="ota.job.create",
        entity_type="ota_job",
        entity_id=str(job.id),
        payload={
            "target_type": payload.target_type,
            "target_ref": payload.target_ref,
            "firmware_version": payload.firmware_version,
        },
    )
    await db.commit()
    await db.refresh(job)
    return job
