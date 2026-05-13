from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import require_roles
from app.core.rbac import (
    FACILITY_MANAGEMENT_ROLES,
    ROLE_LABELS,
    ROLE_SET,
    SYSTEM_ADMIN,
    SYSTEM_ADMIN_ROLES,
    normalize_role,
)
from app.core.security import hash_password
from app.db.session import get_db
from app.models import AccessRequest, AuditLog, Device, FirmwareVersion, Notification, Room, SimulationNode, User
from app.schemas import (
    AccessRequestDecision,
    AccessRequestOut,
    AuditLogOut,
    FirmwareVersionCreate,
    FirmwareVersionOut,
    NotificationOut,
    RoleOptionOut,
    SimulationNodeApprovalRequest,
    SimulationNodeDecisionRequest,
    SimulationNodeOut,
    UserCreate,
    UserOut,
    UserUpdate,
)
from app.services.audit_service import audit_service

router = APIRouter(prefix="/admin", tags=["admin"])


def _node_meta(node: SimulationNode) -> dict:
    payload = node.last_payload if isinstance(node.last_payload, dict) else {}
    if isinstance(payload.get("meta"), dict):
        return dict(payload["meta"])
    return {}


def _latest_payload(node: SimulationNode) -> dict:
    payload = node.last_payload if isinstance(node.last_payload, dict) else {}
    if isinstance(payload.get("latest_event"), dict):
        return dict(payload["latest_event"])
    return dict(payload)


def _set_node_meta(node: SimulationNode, **updates) -> None:
    meta = _node_meta(node)
    for key, value in updates.items():
        if value is None:
            meta.pop(key, None)
        else:
            meta[key] = value
    node.last_payload = {
        "meta": meta,
        "latest_event": _latest_payload(node),
    }


def _serialize_node(node: SimulationNode) -> SimulationNodeOut:
    meta = _node_meta(node)
    room = node.room
    linked_device = node.linked_device
    return SimulationNodeOut(
        id=node.id,
        node_id=node.node_id,
        draft_reference=node.node_id,
        label=node.label,
        room_id=node.room_id,
        room_code=room.room_code if room else None,
        room_name=room.name if room else None,
        sensor_types=list(node.sensor_types or []),
        status=node.status,
        approval_status=meta.get("approval_status", "draft"),
        auto_mode=bool(meta.get("auto_mode", False)),
        paused=bool(meta.get("paused", False)),
        linked_device_id=node.linked_device_id,
        linked_device_identifier=linked_device.device_id if linked_device else None,
        official_device_id=(linked_device.device_id if linked_device else None)
        or meta.get("official_device_id"),
        notes=node.notes,
        last_event_type=node.last_event_type,
        last_payload=_latest_payload(node),
        submitted_for_approval_at=_parse_iso_datetime(meta.get("submitted_for_approval_at")),
        approved_at=_parse_iso_datetime(meta.get("approved_at")),
        approved_by=meta.get("approved_by"),
        rejected_at=_parse_iso_datetime(meta.get("rejected_at")),
        rejected_by=meta.get("rejected_by"),
        decision_notes=meta.get("decision_notes"),
        created_at=node.created_at,
        updated_at=node.updated_at,
    )


def _parse_iso_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


async def _get_node_draft(db: AsyncSession, node_id: str) -> SimulationNode | None:
    return (
        await db.execute(
            select(SimulationNode)
            .options(
                selectinload(SimulationNode.room),
                selectinload(SimulationNode.linked_device),
            )
            .where(SimulationNode.node_id == node_id)
        )
    ).scalar_one_or_none()


async def _resolve_room(
    db: AsyncSession,
    *,
    room_id: int | None,
    room_code: str | None,
) -> Room | None:
    query = select(Room)
    if room_id is not None:
        query = query.where(Room.id == room_id)
    elif room_code:
        query = query.where(Room.room_code == room_code)
    else:
        return None
    return (await db.execute(query)).scalar_one_or_none()


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
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
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
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    return (
        await db.execute(select(AuditLog).order_by(desc(AuditLog.id)).limit(limit))
    ).scalars().all()


@router.get("/notifications", response_model=list[NotificationOut])
async def list_notifications(
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    return (
        await db.execute(select(Notification).order_by(desc(Notification.id)).limit(limit))
    ).scalars().all()


@router.get("/access-requests", response_model=list[AccessRequestOut])
async def list_access_requests(
    status: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    query = select(AccessRequest).order_by(desc(AccessRequest.id))
    if status:
        query = query.where(AccessRequest.status == status)
    return (await db.execute(query.limit(250))).scalars().all()


@router.patch("/access-requests/{request_id}", response_model=AccessRequestOut)
async def decide_access_request(
    request_id: int,
    payload: AccessRequestDecision,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_roles(*SYSTEM_ADMIN_ROLES)),
):
    obj = await db.get(AccessRequest, request_id)
    if not obj:
        raise HTTPException(status_code=404, detail="Access request not found")

    obj.status = payload.status
    obj.reviewer_notes = payload.reviewer_notes
    obj.reviewed_by = actor.email
    obj.reviewed_at = datetime.now(timezone.utc)

    await audit_service.log(
        db,
        actor=actor.email,
        action="access_request.review",
        entity_type="access_request",
        entity_id=str(request_id),
        payload={
            "status": payload.status,
            "reviewer_notes": payload.reviewer_notes,
            "email": obj.email,
            "requested_role": obj.requested_role,
        },
    )
    await db.commit()
    await db.refresh(obj)
    return obj


@router.get("/node-drafts", response_model=list[SimulationNodeOut])
async def list_node_drafts(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    drafts = (
        await db.execute(
            select(SimulationNode)
            .options(
                selectinload(SimulationNode.room),
                selectinload(SimulationNode.linked_device),
            )
            .order_by(SimulationNode.id.desc())
        )
    ).scalars().all()
    return [_serialize_node(item) for item in drafts]


@router.post("/node-drafts/{node_id}/approve", response_model=SimulationNodeOut)
async def approve_node_draft(
    node_id: str,
    payload: SimulationNodeApprovalRequest,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    node = await _get_node_draft(db, node_id)
    if not node:
        raise HTTPException(status_code=404, detail="Simulation node draft not found")

    room = await _resolve_room(db, room_id=payload.room_id, room_code=payload.room_code)
    if not room:
        room = node.room
    if not room:
        raise HTTPException(status_code=422, detail="A room assignment is required before approval")

    device = (
        await db.execute(select(Device).where(Device.device_id == payload.official_device_id))
    ).scalar_one_or_none()
    if not device:
        device = Device(
            room_id=room.id,
            device_id=payload.official_device_id,
            device_type=payload.device_type,
            firmware_version=payload.firmware_version,
            status="online",
        )
        db.add(device)
        await db.flush()
    else:
        device.room_id = room.id
        device.device_type = payload.device_type or device.device_type
        device.firmware_version = payload.firmware_version or device.firmware_version
        device.status = "online"

    node.room_id = room.id
    node.linked_device_id = device.id
    node.status = "active"
    if payload.notes:
        node.notes = payload.notes
    _set_node_meta(
        node,
        approval_status="approved",
        approved_at=datetime.now(timezone.utc).isoformat(),
        approved_by=actor.email,
        rejected_at=None,
        rejected_by=None,
        decision_notes=payload.notes,
        official_device_id=device.device_id,
    )

    await audit_service.log(
        db,
        actor=actor.email,
        action="simulation_node.approve",
        entity_type="simulation_node",
        entity_id=str(node.id),
        payload={
            "draft_reference": node.node_id,
            "official_device_id": device.device_id,
            "room_id": room.id,
            "device_id": device.id,
        },
    )
    await db.commit()
    node = await _get_node_draft(db, node_id)
    if not node:
        raise HTTPException(status_code=500, detail="Simulation node draft approved but could not be reloaded")
    return _serialize_node(node)


@router.post("/node-drafts/{node_id}/reject", response_model=SimulationNodeOut)
async def reject_node_draft(
    node_id: str,
    payload: SimulationNodeDecisionRequest,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    node = await _get_node_draft(db, node_id)
    if not node:
        raise HTTPException(status_code=404, detail="Simulation node draft not found")
    if node.linked_device_id:
        raise HTTPException(status_code=409, detail="Approved or linked nodes cannot be rejected without unlinking the live device")

    node.status = "rejected"
    if payload.notes:
        node.notes = payload.notes
    _set_node_meta(
        node,
        approval_status="rejected",
        rejected_at=datetime.now(timezone.utc).isoformat(),
        rejected_by=actor.email,
        decision_notes=payload.notes,
    )

    await audit_service.log(
        db,
        actor=actor.email,
        action="simulation_node.reject",
        entity_type="simulation_node",
        entity_id=str(node.id),
        payload={
            "draft_reference": node.node_id,
            "notes": payload.notes,
        },
    )
    await db.commit()
    node = await _get_node_draft(db, node_id)
    if not node:
        raise HTTPException(status_code=500, detail="Simulation node draft rejected but could not be reloaded")
    return _serialize_node(node)


@router.delete("/node-drafts/{node_id}", status_code=204)
async def delete_node_draft(
    node_id: str,
    db: AsyncSession = Depends(get_db),
    actor: User = Depends(require_roles(*FACILITY_MANAGEMENT_ROLES)),
):
    node = await _get_node_draft(db, node_id)
    if not node:
        raise HTTPException(status_code=404, detail="Simulation node draft not found")

    await audit_service.log(
        db,
        actor=actor.email,
        action="simulation_node.delete_by_admin",
        entity_type="simulation_node",
        entity_id=str(node.id),
        payload={
            "draft_reference": node.node_id,
            "linked_device_id": node.linked_device_id,
        },
    )
    await db.delete(node)
    await db.commit()
