from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import require_roles
from app.core.rbac import ROLE_LABELS, ROLE_SET, SYSTEM_ADMIN, SYSTEM_ADMIN_ROLES, normalize_role
from app.core.security import hash_password
from app.db.session import get_db
from app.models import AuditLog, FirmwareVersion, Notification, User
from app.schemas import (
    AuditLogOut,
    FirmwareVersionCreate,
    FirmwareVersionOut,
    NotificationOut,
    RoleOptionOut,
    UserCreate,
    UserOut,
    UserUpdate,
)
from app.services.audit_service import audit_service

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/roles", response_model=list[RoleOptionOut])
async def list_roles(
    user: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    return [
        RoleOptionOut(value=value, label=label)
        for value, label in ROLE_LABELS.items()
    ]


@router.get("/users", response_model=list[UserOut])
async def list_users(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    users = (await db.execute(select(User).order_by(User.id.asc()))).scalars().all()
    for item in users:
        item.role = normalize_role(item.role)
    return users


@router.post("/users", response_model=UserOut, status_code=201)
async def create_user(
    payload: UserCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    normalized_role = normalize_role(payload.role)
    if normalized_role not in ROLE_SET:
        raise HTTPException(status_code=422, detail="Unsupported role")

    existing = (
        await db.execute(select(User).where(User.email == payload.email))
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=409, detail="A user with this email already exists")

    obj = User(
        email=payload.email,
        full_name=payload.full_name,
        password_hash=hash_password(payload.password),
        role=normalized_role,
        is_active=payload.is_active,
    )
    db.add(obj)
    await db.flush()
    await audit_service.log(
        db,
        actor=user.email,
        action="user.create",
        entity_type="user",
        entity_id=str(obj.id),
        payload={
            "email": payload.email,
            "full_name": payload.full_name,
            "role": normalized_role,
            "is_active": payload.is_active,
        },
    )
    await db.commit()
    await db.refresh(obj)
    obj.role = normalized_role
    return obj


@router.patch("/users/{user_id}", response_model=UserOut)
async def update_user(
    user_id: int,
    payload: UserUpdate,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    obj = await db.get(User, user_id)
    if not obj:
        raise HTTPException(status_code=404, detail="User not found")

    original_role = normalize_role(obj.role)
    changes = payload.model_dump(exclude_none=True)
    if "role" in changes:
        changes["role"] = normalize_role(changes["role"])
        if changes["role"] not in ROLE_SET:
            raise HTTPException(status_code=422, detail="Unsupported role")

    if "password" in changes:
        obj.password_hash = hash_password(changes.pop("password"))

    for field, value in changes.items():
        setattr(obj, field, value)

    updated_role = normalize_role(obj.role)
    if original_role == SYSTEM_ADMIN and (updated_role != SYSTEM_ADMIN or obj.is_active is False):
        active_admins = (
            await db.execute(
                select(func.count())
                .select_from(User)
                .where(
                    User.id != obj.id,
                    User.is_active.is_(True),
                    User.role.in_([SYSTEM_ADMIN, "admin"]),
                )
            )
        ).scalar_one()
        if active_admins == 0:
            raise HTTPException(status_code=400, detail="At least one active system admin must remain")

    await audit_service.log(
        db,
        actor=actor.email,
        action="user.update",
        entity_type="user",
        entity_id=str(user_id),
        payload=changes,
    )
    await db.commit()
    await db.refresh(obj)
    obj.role = normalize_role(obj.role)
    return obj


@router.delete("/users/{user_id}", status_code=204)
async def delete_user(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    obj = await db.get(User, user_id)
    if not obj:
        raise HTTPException(status_code=404, detail="User not found")
    if obj.id == actor.id:
        raise HTTPException(status_code=400, detail="The current system admin cannot delete their own account")

    normalized_role = normalize_role(obj.role)
    if normalized_role == SYSTEM_ADMIN:
        active_admins = (
            await db.execute(
                select(func.count())
                .select_from(User)
                .where(
                    User.id != obj.id,
                    User.is_active.is_(True),
                    User.role.in_([SYSTEM_ADMIN, "admin"]),
                )
            )
        ).scalar_one()
        if active_admins == 0:
            raise HTTPException(status_code=400, detail="At least one active system admin must remain")

    await audit_service.log(
        db,
        actor=actor.email,
        action="user.delete",
        entity_type="user",
        entity_id=str(user_id),
        payload={"email": obj.email, "role": normalized_role},
    )
    await db.delete(obj)
    await db.commit()


@router.get("/firmware", response_model=list[FirmwareVersionOut])
async def list_firmware(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    return (
        await db.execute(select(FirmwareVersion).order_by(desc(FirmwareVersion.id)))
    ).scalars().all()


@router.post("/firmware", response_model=FirmwareVersionOut, status_code=201)
async def create_firmware(
    payload: FirmwareVersionCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    existing = (
        await db.execute(
            select(FirmwareVersion).where(FirmwareVersion.version == payload.version)
        )
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=409, detail="Firmware version already exists")

    if payload.is_active:
        current_active = (
            await db.execute(select(FirmwareVersion).where(FirmwareVersion.is_active.is_(True)))
        ).scalars().all()
        for item in current_active:
            item.is_active = False

    obj = FirmwareVersion(**payload.model_dump())
    db.add(obj)
    await db.flush()
    await audit_service.log(
        db,
        actor=user.email,
        action="firmware.create",
        entity_type="firmware_version",
        entity_id=str(obj.id),
        payload=payload.model_dump(),
    )
    await db.commit()
    await db.refresh(obj)
    return obj


@router.post("/firmware/{firmware_id}/activate", response_model=FirmwareVersionOut)
async def activate_firmware(
    firmware_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    obj = await db.get(FirmwareVersion, firmware_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Firmware version not found")

    current_active = (
        await db.execute(select(FirmwareVersion).where(FirmwareVersion.is_active.is_(True)))
    ).scalars().all()
    for item in current_active:
        item.is_active = False
    obj.is_active = True

    await audit_service.log(
        db,
        actor=user.email,
        action="firmware.activate",
        entity_type="firmware_version",
        entity_id=str(firmware_id),
        payload={"version": obj.version},
    )
    await db.commit()
    await db.refresh(obj)
    return obj


@router.delete("/firmware/{firmware_id}", status_code=204)
async def delete_firmware(
    firmware_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    obj = await db.get(FirmwareVersion, firmware_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Firmware version not found")

    await audit_service.log(
        db,
        actor=user.email,
        action="firmware.delete",
        entity_type="firmware_version",
        entity_id=str(firmware_id),
        payload={"version": obj.version},
    )
    await db.delete(obj)
    await db.commit()


@router.get("/audit-logs", response_model=list[AuditLogOut])
async def list_audit_logs(
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    return (
        await db.execute(select(AuditLog).order_by(desc(AuditLog.id)).limit(limit))
    ).scalars().all()


@router.get("/notifications", response_model=list[NotificationOut])
async def list_notifications(
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    return (
        await db.execute(select(Notification).order_by(desc(Notification.id)).limit(limit))
    ).scalars().all()
