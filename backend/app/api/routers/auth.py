from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.db.session import get_db
from app.models import AccessRequest, User
from app.schemas import AccessRequestCreate, AccessRequestOut, LoginRequest, TokenResponse, UserOut
from app.core.rbac import ROLE_SET, normalize_role
from app.core.security import verify_password, create_access_token
from app.api.deps import get_current_user

router = APIRouter(prefix="/auth", tags=["auth"])

@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    user = (await db.execute(select(User).where(User.email == payload.email))).scalar_one_or_none()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="User account is inactive")
    user.role = normalize_role(user.role)
    return TokenResponse(access_token=create_access_token(user.email, {"role": user.role, "user_id": user.id}))

@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(get_current_user)):
    return user


@router.post("/access-requests", response_model=AccessRequestOut, status_code=201)
async def create_access_request(
    payload: AccessRequestCreate,
    db: AsyncSession = Depends(get_db),
):
    requested_role = normalize_role(payload.requested_role)
    if requested_role not in ROLE_SET:
        raise HTTPException(status_code=422, detail="Unsupported requested role")

    existing_user = (
        await db.execute(select(User).where(User.email == payload.email))
    ).scalar_one_or_none()
    if existing_user:
        raise HTTPException(status_code=409, detail="An account already exists for this email")

    existing_request = (
        await db.execute(
            select(AccessRequest).where(
                AccessRequest.email == payload.email,
                AccessRequest.status == "pending",
            )
        )
    ).scalar_one_or_none()
    if existing_request:
        raise HTTPException(status_code=409, detail="A pending access request already exists for this email")

    obj = AccessRequest(
        email=payload.email,
        full_name=payload.full_name,
        requested_role=requested_role,
        justification=payload.justification,
        status="pending",
    )
    db.add(obj)
    await db.commit()
    await db.refresh(obj)
    return obj
