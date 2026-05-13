from sqlalchemy.ext.asyncio import AsyncSession

from app.models import AuditLog


class AuditService:
    async def log(
        self,
        db: AsyncSession,
        *,
        actor: str,
        action: str,
        entity_type: str,
        entity_id: str,
        payload: dict | None = None,
    ) -> AuditLog:
        entry = AuditLog(
            actor=actor,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            payload=payload or {},
        )
        db.add(entry)
        await db.flush()
        return entry


audit_service = AuditService()
