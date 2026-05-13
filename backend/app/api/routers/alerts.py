from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.core.rbac import ALERT_ACK_ROLES, MONITORING_ROLES
from app.schemas import AlertOut, AcknowledgeRequest
from app.api.deps import require_roles
from app.models import User
from app.services.alert_engine import alert_engine
from app.services.audit_service import audit_service
from app.services.dashboard_service import dashboard_service

router = APIRouter(prefix="/alerts", tags=["alerts"])

@router.get("", response_model=list[AlertOut])
async def list_alerts(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    alerts = await dashboard_service.list_alerts(db)
    return [AlertOut.model_validate(alert) for alert in alerts]

@router.post("/{alert_id}/acknowledge", response_model=AlertOut)
async def acknowledge_alert(
    alert_id: int, 
    payload: AcknowledgeRequest | None = None, 
    db: AsyncSession = Depends(get_db), 
    user: User = Depends(require_roles(*ALERT_ACK_ROLES)),
):
    """Acknowledge an alert."""
    actor = payload.actor if payload and payload.actor else user.email
    obj = await alert_engine.acknowledge(db, alert_id, actor)
    if not obj:
        raise HTTPException(status_code=404, detail="Alert not found")
    await audit_service.log(
        db,
        actor=user.email,
        action="alert.acknowledge",
        entity_type="alert",
        entity_id=str(alert_id),
        payload={"actor": actor},
    )
    await db.commit()
    await db.refresh(obj)
    return obj
