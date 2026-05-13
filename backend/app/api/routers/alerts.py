from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.db.session import get_db
from app.models import Alert
from app.schemas import AlertOut, AcknowledgeRequest
from app.api.deps import get_current_user
from app.services.alert_engine import alert_engine

router = APIRouter(prefix="/alerts", tags=["alerts"])

@router.get("", response_model=list[AlertOut])
async def list_alerts(db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    return (await db.execute(select(Alert).order_by(Alert.id.desc()))).scalars().all()

@router.post("/{alert_id}/acknowledge", response_model=AlertOut)
async def acknowledge_alert(
    alert_id: int, 
    payload: AcknowledgeRequest = None, 
    db: AsyncSession = Depends(get_db), 
    user=Depends(get_current_user)
):
    """Acknowledge an alert."""
    actor = payload.actor if payload else "control-room"
    obj = await alert_engine.acknowledge(db, alert_id, actor)
    if not obj:
        raise HTTPException(status_code=404, detail="Alert not found")
    await db.commit()
    await db.refresh(obj)
    return obj
    await db.commit(); await db.refresh(obj); return obj
