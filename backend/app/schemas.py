from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field

# =========================
# AUTH SCHEMAS
# =========================

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class LoginRequest(BaseModel):
    # Changed from EmailStr -> str
    # because admin@alghurair.local fails validation
    email: str
    password: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: str
    full_name: str
    role: str
    is_active: bool


# =========================
# BUILDINGS
# =========================

class BuildingCreate(BaseModel):
    code: str
    name: str


class BuildingOut(BuildingCreate):
    model_config = ConfigDict(from_attributes=True)

    id: int


# =========================
# FLOORS
# =========================

class FloorCreate(BaseModel):
    building_id: int
    level: int
    name: str


class FloorOut(FloorCreate):
    model_config = ConfigDict(from_attributes=True)

    id: int


# =========================
# ROOMS
# =========================

class RoomCreate(BaseModel):
    floor_id: int
    room_code: str
    name: str
    zone: str = "chute-room"


class RoomOut(RoomCreate):
    model_config = ConfigDict(from_attributes=True)

    id: int


# =========================
# DEVICES
# =========================

class DeviceCreate(BaseModel):
    room_id: int
    device_id: str
    device_type: str = "esp32-s3-poe"
    firmware_version: str = "1.0.0"


class DeviceOut(DeviceCreate):
    model_config = ConfigDict(from_attributes=True)

    id: int
    status: str
    last_seen_at: datetime | None = None


# =========================
# ALERTS
# =========================

class AlertOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    room_id: int
    source: str
    category: str
    message: str
    severity: str
    acknowledged: bool
    acknowledged_by: str | None = None
    acknowledged_at: datetime | None = None
    created_at: datetime


class AcknowledgeRequest(BaseModel):
    actor: str = "control-room"


# =========================
# OTA JOBS
# =========================

class OtaJobCreate(BaseModel):
    target_type: str = Field(
        default="room",
        pattern="^(room|building|device)$"
    )

    target_ref: str
    firmware_version: str
    requested_by: str = "admin"


class OtaJobOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    target_type: str
    target_ref: str
    firmware_version: str
    status: str
    progress: int
    requested_by: str
    created_at: datetime


# =========================
# AI EVENTS
# =========================

class AiEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    room_id: int
    camera_id: str
    event_type: str
    confidence: float
    snapshot_url: str | None = None
    payload: dict
    created_at: datetime


# =========================
# ANALYTICS SUMMARY
# =========================

class SummaryOut(BaseModel):
    buildings: int
    floors: int
    rooms: int
    devices: int
    alerts_open: int
    ai_events_24h: int
    ota_jobs_active: int


# =========================
# SENSOR EVENTS
# =========================

class SensorEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    room_id: int
    device_id: int | None = None
    event_type: str
    payload: dict
    severity: str
    created_at: datetime


# =========================
# MAINTENANCE LOGS
# =========================

class MaintenanceLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    room_id: int
    issue: str
    status: str
    notes: str | None = None
    created_at: datetime


# =========================
# NOTIFICATIONS
# =========================

class NotificationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    channel: str
    recipient: str
    title: str
    body: str
    status: str
    created_at: datetime