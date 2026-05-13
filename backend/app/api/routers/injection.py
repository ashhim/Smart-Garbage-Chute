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
    SimulationNodeEmitRequest,
    SimulationNodeOut,
    SimulationNodeRegisterRequest,
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


def _serialize_node(node: SimulationNode) -> SimulationNodeOut:
    room = node.room
    linked_device = node.linked_device
    return SimulationNodeOut(
        id=node.id,
        node_id=node.node_id,
        label=node.label,
        room_id=node.room_id,
        room_code=room.room_code if room else None,
        room_name=room.name if room else None,
        sensor_types=list(node.sensor_types or []),
        status=node.status,
        linked_device_id=node.linked_device_id,
        linked_device_identifier=linked_device.device_id if linked_device else None,
        notes=node.notes,
        last_event_type=node.last_event_type,
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
    existing = await _get_node(db, payload.node_id)
    if existing:
        raise HTTPException(status_code=409, detail="Simulation node already exists")

    room = await _resolve_room(db, room_id=payload.room_id, room_code=payload.room_code)
    sensor_types = payload.sensor_types or DEFAULT_SENSOR_TYPES
    obj = SimulationNode(
        node_id=payload.node_id,
        label=payload.label or payload.node_id,
        room_id=room.id if room else None,
        sensor_types=sensor_types,
        status="staged",
        notes=payload.notes,
    )
    db.add(obj)
    await db.flush()
    await audit_service.log(
        db,
        actor=user.email,
        action="simulation_node.create",
        entity_type="simulation_node",
        entity_id=str(obj.id),
        payload={
            "node_id": payload.node_id,
            "room_id": room.id if room else None,
            "sensor_types": sensor_types,
        },
    )
    await db.commit()
    node = await _get_node(db, payload.node_id)
    if not node:
        raise HTTPException(status_code=500, detail="Simulation node created but could not be reloaded")
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
        raise HTTPException(status_code=422, detail="A room assignment is required before registration")

    device = (
        await db.execute(select(Device).where(Device.device_id == node.node_id))
    ).scalar_one_or_none()
    if not device:
        device = Device(
            room_id=room.id,
            device_id=node.node_id,
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
    node.status = "registered"

    await audit_service.log(
        db,
        actor=user.email,
        action="simulation_node.register",
        entity_type="simulation_node",
        entity_id=str(node.id),
        payload={
            "node_id": node.node_id,
            "room_id": room.id,
            "device_id": device.id,
        },
    )
    await db.commit()
    node = await _get_node(db, node_id)
    if not node:
        raise HTTPException(status_code=500, detail="Simulation node registered but could not be reloaded")
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

    _ensure_event_supported(node, payload.event_type)

    node.status = "active"
    node.last_event_type = payload.event_type
    node.last_payload = payload.payload

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
