from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.core.rbac import MONITORING_ROLES
from app.models import User
from app.schemas import SummaryOut
from app.services.analytics_service import analytics_service
from app.api.deps import require_roles

router = APIRouter(prefix="/analytics", tags=["analytics"])

@router.get("/summary", response_model=SummaryOut)
async def summary(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*MONITORING_ROLES)),
):
    return await analytics_service.summary(db)
