from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.schemas import SummaryOut
from app.services.analytics_service import analytics_service
from app.api.deps import get_current_user

router = APIRouter(prefix="/analytics", tags=["analytics"])

@router.get("/summary", response_model=SummaryOut)
async def summary(db: AsyncSession = Depends(get_db), user=Depends(get_current_user)):
    return await analytics_service.summary(db)
