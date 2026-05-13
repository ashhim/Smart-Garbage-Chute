from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password
from app.models import (
    AiEvent,
    Alert,
    Building,
    Device,
    FirmwareVersion,
    Floor,
    MaintenanceLog,
    Notification,
    OtaJob,
    Room,
    SensorEvent,
    User,
)

DEMO_ADMIN_EMAIL = "admin@alghurair.local"
DEMO_ADMIN_PASSWORD = "Admin@12345"

BUILDING_BLUEPRINTS = (
    {"code": "BLK-01", "name": "Block A - Al Ghurair"},
    {"code": "BLK-02", "name": "Block B - Al Ghurair"},
)

ROOMS_PER_FLOOR = 5
FLOOR_LEVELS = (1, 2, 3)


async def ensure_demo_platform(session: AsyncSession) -> None:
    """Seed and heal demo data without duplicating existing records."""
    await _ensure_admin_user(session)
    rooms_by_code = await _ensure_site_structure(session)
    await _ensure_firmware_catalog(session)
    await _ensure_operational_baseline(session, rooms_by_code)
    await session.commit()


async def _ensure_admin_user(session: AsyncSession) -> None:
    admin = (
        await session.execute(select(User).where(User.email == DEMO_ADMIN_EMAIL))
    ).scalar_one_or_none()
    if admin:
        admin.full_name = admin.full_name or "System Administrator"
        admin.role = admin.role or "admin"
        admin.is_active = True
        return

    session.add(
        User(
            email=DEMO_ADMIN_EMAIL,
            full_name="System Administrator",
            password_hash=hash_password(DEMO_ADMIN_PASSWORD),
            role="admin",
            is_active=True,
        )
    )
    await session.flush()


async def _ensure_site_structure(session: AsyncSession) -> dict[str, Room]:
    buildings_by_code: dict[str, Building] = {}
    for blueprint in BUILDING_BLUEPRINTS:
        building = (
            await session.execute(
                select(Building).where(Building.code == blueprint["code"])
            )
        ).scalar_one_or_none()
        if not building:
            building = Building(code=blueprint["code"], name=blueprint["name"])
            session.add(building)
            await session.flush()
        else:
            building.name = blueprint["name"]
        buildings_by_code[blueprint["code"]] = building

    floors_by_key: dict[tuple[str, int], Floor] = {}
    for blueprint in BUILDING_BLUEPRINTS:
        building = buildings_by_code[blueprint["code"]]
        for level in FLOOR_LEVELS:
            floor = (
                await session.execute(
                    select(Floor).where(
                        Floor.building_id == building.id,
                        Floor.level == level,
                    )
                )
            ).scalar_one_or_none()
            if not floor:
                floor = Floor(building_id=building.id, level=level, name=f"Level {level}")
                session.add(floor)
                await session.flush()
            else:
                floor.name = f"Level {level}"
            floors_by_key[(building.code, level)] = floor

    rooms_by_code: dict[str, Room] = {}
    room_counter = 1
    for blueprint in BUILDING_BLUEPRINTS:
        for level in FLOOR_LEVELS:
            floor = floors_by_key[(blueprint["code"], level)]
            for room_number in range(1, ROOMS_PER_FLOOR + 1):
                room_code = f"CHR_{room_counter:02d}"
                room_name = f"Chute Room {room_counter}"
                room = (
                    await session.execute(select(Room).where(Room.room_code == room_code))
                ).scalar_one_or_none()
                if not room:
                    room = Room(
                        floor_id=floor.id,
                        room_code=room_code,
                        name=room_name,
                        zone="chute-room",
                    )
                    session.add(room)
                    await session.flush()
                else:
                    room.floor_id = floor.id
                    room.name = room_name
                    room.zone = room.zone or "chute-room"
                rooms_by_code[room_code] = room
                room_counter += 1

    for index, room_code in enumerate(sorted(rooms_by_code.keys()), start=1):
        room = rooms_by_code[room_code]
        expected_device_id = f"ESP32-{index:02d}"
        device = (
            await session.execute(select(Device).where(Device.device_id == expected_device_id))
        ).scalar_one_or_none()
        if not device:
            device = (
                await session.execute(
                    select(Device).where(Device.room_id == room.id).order_by(Device.id.asc())
                )
            ).scalars().first()

        if not device:
            device = Device(
                room_id=room.id,
                device_id=expected_device_id,
                device_type="esp32-s3-poe",
                firmware_version="1.2.1",
                status="online",
                last_seen_at=datetime.now(timezone.utc) - timedelta(minutes=index % 7),
            )
            session.add(device)
            await session.flush()
        else:
            device.room_id = room.id
            device.device_type = device.device_type or "esp32-s3-poe"
            device.firmware_version = device.firmware_version or "1.2.1"
            device.status = device.status or "online"
            if device.last_seen_at is None:
                device.last_seen_at = datetime.now(timezone.utc) - timedelta(minutes=index % 7)

    return rooms_by_code


async def _ensure_firmware_catalog(session: AsyncSession) -> None:
    firmware = (
        await session.execute(
            select(FirmwareVersion).where(FirmwareVersion.version == "1.2.1")
        )
    ).scalar_one_or_none()
    if not firmware:
        session.add(
            FirmwareVersion(
                version="1.2.1",
                build_sha="abc123def456",
                artifact_url="https://example.com/firmware/v1.2.1.bin",
                notes="Stable release for demo ESP32-S3 Ethernet PoE nodes.",
                is_active=True,
            )
        )
        await session.flush()
        return

    firmware.build_sha = "abc123def456"
    firmware.artifact_url = "https://example.com/firmware/v1.2.1.bin"
    firmware.is_active = True
    firmware.notes = firmware.notes or "Stable release for demo ESP32-S3 Ethernet PoE nodes."


async def _ensure_operational_baseline(
    session: AsyncSession,
    rooms_by_code: dict[str, Room],
) -> None:
    now = datetime.now(timezone.utc)

    if (
        await session.execute(select(SensorEvent.id).limit(1))
    ).scalar_one_or_none() is None:
        sensor_seed = [
            ("CHR_01", "heartbeat", "info", {"heartbeat": True, "temperature_c": 22.8, "humidity_pct": 48}),
            ("CHR_03", "blockage", "high", {"blockage": True, "distance_cm": 14, "sensor": "ultrasonic"}),
            ("CHR_07", "door_prolonged_open", "high", {"door_open_seconds": 196, "sensor": "magnetic_contact"}),
            ("CHR_11", "leak", "critical", {"leak_detected": True, "sensor": "floor_probe"}),
            ("CHR_14", "overflow", "high", {"overflow_percent": 91, "sensor": "cctv_assist"}),
            ("CHR_18", "motion", "info", {"motion_detected": True, "sensor": "pir"}),
        ]

        for room_code, event_type, severity, payload in sensor_seed:
            room = rooms_by_code[room_code]
            device = (
                await session.execute(select(Device).where(Device.room_id == room.id))
            ).scalars().first()
            if device:
                device.last_seen_at = now - timedelta(minutes=(room.id % 9) + 1)
            session.add(
                SensorEvent(
                    room_id=room.id,
                    device_id=device.id if device else None,
                    event_type=event_type,
                    severity=severity,
                    payload={
                        **payload,
                        "room_code": room.room_code,
                        "source": "demo_seed",
                    },
                    created_at=now - timedelta(minutes=room.id),
                    updated_at=now - timedelta(minutes=room.id),
                )
            )

    if (await session.execute(select(Alert.id).limit(1))).scalar_one_or_none() is None:
        alert_seed = [
            ("CHR_03", "blockage", "Chute blockage threshold exceeded in Block A / Level 1.", "high", False, None),
            ("CHR_07", "door_prolonged_open", "Door remained open beyond the configured safety window.", "high", False, None),
            ("CHR_11", "leak", "Liquid detected on chute room floor. Cleaning escalation required.", "critical", False, None),
            ("CHR_14", "overflow", "Overflow condition acknowledged during prior inspection cycle.", "medium", True, "supervisor"),
        ]

        for offset, (room_code, category, message, severity, acknowledged, actor) in enumerate(alert_seed, start=1):
            alert = Alert(
                room_id=rooms_by_code[room_code].id,
                source="demo_seed",
                category=category,
                message=message,
                severity=severity,
                acknowledged=acknowledged,
                acknowledged_by=actor,
                acknowledged_at=(now - timedelta(hours=3)) if acknowledged else None,
                created_at=now - timedelta(minutes=offset * 11),
                updated_at=now - timedelta(minutes=offset * 11),
            )
            session.add(alert)

    if (await session.execute(select(AiEvent.id).limit(1))).scalar_one_or_none() is None:
        ai_seed = [
            ("CHR_03", "CAM-CHR_03", "garbage_on_floor", 0.94, {"bounding_boxes": 1}),
            ("CHR_14", "CAM-CHR_14", "overflow", 0.91, {"bounding_boxes": 2}),
            ("CHR_21", "CAM-CHR_21", "misuse", 0.88, {"person_detected": True}),
        ]
        for offset, (room_code, camera_id, event_type, confidence, payload) in enumerate(ai_seed, start=1):
            session.add(
                AiEvent(
                    room_id=rooms_by_code[room_code].id,
                    camera_id=camera_id,
                    event_type=event_type,
                    confidence=confidence,
                    snapshot_url=f"/snapshots/{room_code.lower()}-{event_type}.jpg",
                    payload={
                        **payload,
                        "room_code": room_code,
                        "source": "demo_seed",
                    },
                    created_at=now - timedelta(minutes=offset * 17),
                    updated_at=now - timedelta(minutes=offset * 17),
                )
            )

    if (await session.execute(select(OtaJob.id).limit(1))).scalar_one_or_none() is None:
        session.add_all(
            [
                OtaJob(
                    target_type="room",
                    target_ref="CHR_05",
                    firmware_version="1.2.1",
                    status="running",
                    progress=45,
                    requested_by="system",
                    created_at=now - timedelta(hours=1),
                    updated_at=now - timedelta(minutes=12),
                ),
                OtaJob(
                    target_type="building",
                    target_ref="BLK-02",
                    firmware_version="1.2.1",
                    status="completed",
                    progress=100,
                    requested_by="system",
                    created_at=now - timedelta(hours=10),
                    updated_at=now - timedelta(hours=2),
                ),
            ]
        )

    if (await session.execute(select(MaintenanceLog.id).limit(1))).scalar_one_or_none() is None:
        session.add_all(
            [
                MaintenanceLog(
                    room_id=rooms_by_code["CHR_03"].id,
                    issue="Clear compaction at chute inlet and verify ultrasonic calibration.",
                    status="open",
                    notes="Awaiting housekeeping team dispatch.",
                ),
                MaintenanceLog(
                    room_id=rooms_by_code["CHR_14"].id,
                    issue="Inspect recurring overflow hotspot noted by CCTV analytics.",
                    status="in_progress",
                    notes="Supervisor review scheduled for next cleaning round.",
                ),
            ]
        )

    if (await session.execute(select(Notification.id).limit(1))).scalar_one_or_none() is None:
        session.add_all(
            [
                Notification(
                    channel="email",
                    recipient="ops@alghurair.local",
                    title="[HIGH] CHR_03 blockage",
                    body="Chute blockage threshold exceeded in Block A / Level 1.",
                    status="sent",
                    meta={"room_code": "CHR_03", "source": "demo_seed"},
                ),
                Notification(
                    channel="whatsapp",
                    recipient="cleaning_team_alpha",
                    title="[CRITICAL] CHR_11 leak",
                    body="Liquid detected on chute room floor. Cleaning escalation required.",
                    status="sent",
                    meta={"room_code": "CHR_11", "source": "demo_seed"},
                ),
            ]
        )

    stale_room_codes = {"CHR_09", "CHR_25"}
    for room_code in stale_room_codes:
        room = rooms_by_code.get(room_code)
        if not room:
            continue
        device = (
            await session.execute(select(Device).where(Device.room_id == room.id))
        ).scalars().first()
        if device:
            device.status = "offline"
            device.last_seen_at = now - timedelta(hours=4)
