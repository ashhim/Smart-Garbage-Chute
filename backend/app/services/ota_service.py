from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models import OtaJob, OtaLog, Device, Room
from app.services.broadcaster import broadcaster

class OtaService:
    async def create_job(self, db: AsyncSession, target_type: str, target_ref: str, firmware_version: str, requested_by: str) -> OtaJob:
        job = OtaJob(target_type=target_type, target_ref=target_ref, firmware_version=firmware_version, status="queued", progress=0, requested_by=requested_by)
        db.add(job)
        await db.flush()
        db.add(OtaLog(ota_job_id=job.id, level="info", message=f"OTA job queued for {target_type}:{target_ref} -> {firmware_version}"))
        await broadcaster.publish("ota", {"type": "ota.created", "job_id": job.id, "target_type": target_type, "target_ref": target_ref, "firmware_version": firmware_version})
        return job

    async def advance_job(self, db: AsyncSession, job: OtaJob, progress: int, status: str | None = None, message: str | None = None) -> None:
        job.progress = progress
        if status:
            job.status = status
        if message:
            db.add(OtaLog(ota_job_id=job.id, level="info", message=message))
        await broadcaster.publish("ota", {"type": "ota.progress", "job_id": job.id, "progress": progress, "status": job.status})

ota_service = OtaService()
