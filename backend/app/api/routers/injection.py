from datetime import datetime, timezone
from secrets import randbelow

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import require_roles
from app.core.rbac import SIMULATION_ROLES
from app.db.session import get_db
from app.models import Device, Room, SimulationNode, User
from app.schemas import (
    SimulationNodeCreate,
    SimulationNodeDecisionRequest,
    SimulationNodeEmitRequest,
    SimulationNodeOut,
    SimulationNodeRegisterRequest,
    SimulationNodeUpdate,
)
from app.services.audit_service import audit_service
from app.services.simulation_service import simulation_service

router = APIRouter(prefix="/injection", tags=["injection"])

DEFAULT_SENSOR_TYPES = [
    "ir_blockage",
    "ultrasonic",
    "door_contact",
    "leak_sensor",
    "heartbeat",
    "cctv_ai",
]

EVENT_SENSOR_REQUIREMENTS = {
    "heartbeat": {"heartbeat"},
    "door_open": {"door_contact"},
    "door_prolonged_open": {"door_contact"},
    "blockage": {"ir_blockage", "ultrasonic"},
    "overflow": {"ultrasonic", "cctv_ai"},
    "leak": {"leak_sensor"},
    "motion": {"cctv_ai"},
    "garbage_left": {"cctv_ai"},
    "misuse": {"cctv_ai"},
}


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


async def _get_node(db: AsyncSession, node_id: str) -> SimulationNode | None:
    return (
        await db.execute(
            select(SimulationNode)
            .execution_options(populate_existing=True)
            .options(
                selectinload(SimulationNode.room),
                selectinload(SimulationNode.linked_device),
            )
            .where(SimulationNode.node_id == node_id)
        )
    ).scalar_one_or_none()


def _parse_iso_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


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


def _generate_draft_reference() -> str:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    return f"DRAFT-{timestamp}-{randbelow(10_000):04d}"


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


def _ensure_event_supported(node: SimulationNode, event_type: str) -> None:
    required = EVENT_SENSOR_REQUIREMENTS.get(event_type)
    if not required:
        raise HTTPException(status_code=422, detail="Unsupported simulation event type")

    sensors = set(node.sensor_types or [])
    if sensors.intersection(required):
        return

    raise HTTPException(
        status_code=400,
        detail=f"Node {node.node_id} does not have the required sensor set for {event_type}",
    )


@router.get("/nodes", response_model=list[SimulationNodeOut])
async def list_nodes(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SIMULATION_ROLES)),
):
    nodes = (
        await db.execute(
            select(SimulationNode)
            .options(
                selectinload(SimulationNode.room),
                selectinload(SimulationNode.linked_device),
            )
            .order_by(SimulationNode.id.desc())
        )
    ).scalars().all()
    return [_serialize_node(node) for node in nodes]


@router.post("/nodes", response_model=SimulationNodeOut, status_code=201)
async def create_node(
    payload: SimulationNodeCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SIMULATION_ROLES)),
):
    draft_reference = payload.node_id or _generate_draft_reference()
    existing = await _get_node(db, draft_reference)
    if existing:
        raise HTTPException(status_code=409, detail="Simulation node already exists")

    room = await _resolve_room(db, room_id=payload.room_id, room_code=payload.room_code)
    sensor_types = payload.sensor_types or DEFAULT_SENSOR_TYPES
    obj = SimulationNode(
        node_id=draft_reference,
        label=payload.label or "Pending Node Draft",
        room_id=room.id if room else None,
        sensor_types=sensor_types,
        status="draft",
        notes=payload.notes,
    )
    db.add(obj)
    await db.flush()
    _set_node_meta(
        obj,
        approval_status="draft",
        auto_mode=payload.auto_mode,
        paused=False,
    )
    await audit_service.log(
        db,
        actor=user.email,
        action="simulation_node.create",
        entity_type="simulation_node",
        entity_id=str(obj.id),
        payload={
            "node_id": draft_reference,
            "room_id": room.id if room else None,
            "sensor_types": sensor_types,
            "auto_mode": payload.auto_mode,
        },
    )
    await db.commit()
    node = await _get_node(db, draft_reference)
    if not node:
        raise HTTPException(status_code=500, detail="Simulation node created but could not be reloaded")
    return _serialize_node(node)


@router.patch("/nodes/{node_id}", response_model=SimulationNodeOut)
async def update_node(
    node_id: str,
    payload: SimulationNodeUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SIMULATION_ROLES)),
):
    node = await _get_node(db, node_id)
    if not node:
        raise HTTPException(status_code=404, detail="Simulation node not found")

    if payload.room_id is not None or payload.room_code is not None:
        room = await _resolve_room(db, room_id=payload.room_id, room_code=payload.room_code)
        if not room:
            raise HTTPException(status_code=404, detail="Assigned room was not found")
        node.room_id = room.id

    if payload.label is not None:
        node.label = payload.label or "Pending Node Draft"
    if payload.sensor_types is not None:
        node.sensor_types = payload.sensor_types or DEFAULT_SENSOR_TYPES
    if payload.notes is not None:
        node.notes = payload.notes

    meta_updates: dict[str, object] = {}
    if payload.auto_mode is not None:
        meta_updates["auto_mode"] = payload.auto_mode
    if payload.paused is not None:
        meta_updates["paused"] = payload.paused
        if payload.paused:
            node.status = "paused"
        elif node.linked_device_id:
            node.status = "active"
        else:
            node.status = str(_node_meta(node).get("approval_status", "draft"))
    if meta_updates:
        _set_node_meta(node, **meta_updates)

    await audit_service.log(
        db,
        actor=user.email,
        action="simulation_node.update",
        entity_type="simulation_node",
        entity_id=str(node.id),
        payload={
            "room_id": node.room_id,
            "sensor_types": list(node.sensor_types or []),
            "auto_mode": _node_meta(node).get("auto_mode", False),
            "paused": _node_meta(node).get("paused", False),
        },
    )
    await db.commit()
    node = await _get_node(db, node_id)
    if not node:
        raise HTTPException(status_code=500, detail="Simulation node updated but could not be reloaded")
    return _serialize_node(node)


@router.post("/nodes/{node_id}/register", response_model=SimulationNodeOut)
async def register_node(
    node_id: str,
    payload: SimulationNodeRegisterRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SIMULATION_ROLES)),
):
    node = await _get_node(db, node_id)
    if not node:
        raise HTTPException(status_code=404, detail="Simulation node not found")

    room = await _resolve_room(db, room_id=payload.room_id, room_code=payload.room_code)
    if not room:
        room = node.room
    if not room:
        raise HTTPException(status_code=422, detail="A room assignment is required before approval submission")

    node.room_id = room.id
    if not payload.official_device_id:
        node.status = "pending_approval"
        _set_node_meta(
            node,
            approval_status="pending",
            submitted_for_approval_at=datetime.now(timezone.utc).isoformat(),
            decision_notes=payload.notes,
        )
        await audit_service.log(
            db,
            actor=user.email,
            action="simulation_node.submit_approval",
            entity_type="simulation_node",
            entity_id=str(node.id),
            payload={
                "draft_reference": node.node_id,
                "room_id": room.id,
                "notes": payload.notes,
            },
        )
        await db.commit()
        node = await _get_node(db, node_id)
        if not node:
            raise HTTPException(status_code=500, detail="Simulation node approval request submitted but could not be reloaded")
        return _serialize_node(node)

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

    node.linked_device_id = device.id
    node.status = "active"
    _set_node_meta(
        node,
        approval_status="approved",
        approved_at=datetime.now(timezone.utc).isoformat(),
        approved_by=user.email,
        official_device_id=device.device_id,
        decision_notes=payload.notes,
    )

    await audit_service.log(
        db,
        actor=user.email,
        action="simulation_node.register",
        entity_type="simulation_node",
        entity_id=str(node.id),
        payload={
            "draft_reference": node.node_id,
            "room_id": room.id,
            "device_id": device.id,
            "official_device_id": device.device_id,
        },
    )
    await db.commit()
    node = await _get_node(db, node_id)
    if not node:
        raise HTTPException(status_code=500, detail="Simulation node registered but could not be reloaded")
    return _serialize_node(node)


@router.post("/nodes/{node_id}/submit-approval", response_model=SimulationNodeOut)
async def submit_node_for_approval(
    node_id: str,
    payload: SimulationNodeDecisionRequest | None = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SIMULATION_ROLES)),
):
    node = await _get_node(db, node_id)
    if not node:
        raise HTTPException(status_code=404, detail="Simulation node not found")
    if not node.room_id:
        raise HTTPException(status_code=422, detail="Assign the draft to a room before submitting for approval")

    node.status = "pending_approval"
    _set_node_meta(
        node,
        approval_status="pending",
        submitted_for_approval_at=datetime.now(timezone.utc).isoformat(),
        decision_notes=payload.notes if payload else None,
    )
    await audit_service.log(
        db,
        actor=user.email,
        action="simulation_node.submit_approval",
        entity_type="simulation_node",
        entity_id=str(node.id),
        payload={
            "draft_reference": node.node_id,
            "room_id": node.room_id,
            "notes": payload.notes if payload else None,
        },
    )
    await db.commit()
    node = await _get_node(db, node_id)
    if not node:
        raise HTTPException(status_code=500, detail="Simulation node approval request submitted but could not be reloaded")
    return _serialize_node(node)


@router.post("/nodes/{node_id}/emit")
async def emit_node_event(
    node_id: str,
    payload: SimulationNodeEmitRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SIMULATION_ROLES)),
):
    node = await _get_node(db, node_id)
    if not node:
        raise HTTPException(status_code=404, detail="Simulation node not found")
    if not node.room_id:
        raise HTTPException(status_code=422, detail="Simulation node must be assigned to a room before emitting events")
    if node.status == "rejected":
        raise HTTPException(status_code=409, detail="Rejected drafts cannot emit events until they are resubmitted")

    _ensure_event_supported(node, payload.event_type)

    if node.status not in {"paused", "pending_approval"}:
        node.status = "active"
    node.last_event_type = payload.event_type
    node.last_payload = {
        "meta": _node_meta(node),
        "latest_event": payload.payload,
    }

    result = await simulation_service.emit(
        db,
        room_id=node.room_id,
        event_type=payload.event_type,
        severity=payload.severity,
        source="node_injection",
        confidence=payload.confidence,
        device_id=node.linked_device.device_id if node.linked_device else node.node_id,
        payload={
            **payload.payload,
            "simulated_node_id": node.node_id,
            "configured_sensors": list(node.sensor_types or []),
            "approval_status": _node_meta(node).get("approval_status", "draft"),
        },
    )

    await audit_service.log(
        db,
        actor=user.email,
        action="simulation_node.emit",
        entity_type="simulation_node",
        entity_id=str(node.id),
        payload={
            "event_type": payload.event_type,
            "severity": payload.severity,
            "result": result,
        },
    )
    await db.commit()
    return {
        **result,
        "node_id": node.node_id,
        "configured_sensors": list(node.sensor_types or []),
    }


@router.delete("/nodes/{node_id}", status_code=204)
async def delete_node(
    node_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_roles(*SIMULATION_ROLES)),
):
    node = await _get_node(db, node_id)
    if not node:
        raise HTTPException(status_code=404, detail="Simulation node not found")

    await audit_service.log(
        db,
        actor=user.email,
        action="simulation_node.delete",
        entity_type="simulation_node",
        entity_id=str(node.id),
        payload={"node_id": node.node_id},
    )
    await db.delete(node)
    await db.commit()
