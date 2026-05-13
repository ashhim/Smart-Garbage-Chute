from __future__ import annotations
from datetime import datetime
from sqlalchemy import String, Boolean, Integer, DateTime, ForeignKey, Text, Float, JSON, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

class User(Base, TimestampMixin):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(255), default="Admin")
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(50), default="viewer")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

class Building(Base, TimestampMixin):
    __tablename__ = "buildings"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    code: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(255), index=True)
    floors = relationship("Floor", back_populates="building", cascade="all, delete-orphan")

class Floor(Base, TimestampMixin):
    __tablename__ = "floors"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    building_id: Mapped[int] = mapped_column(ForeignKey("buildings.id", ondelete="CASCADE"))
    level: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(String(255))
    building = relationship("Building", back_populates="floors")
    rooms = relationship("Room", back_populates="floor", cascade="all, delete-orphan")
    __table_args__ = (UniqueConstraint("building_id", "level", name="uq_building_floor_level"),)

class Room(Base, TimestampMixin):
    __tablename__ = "rooms"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    floor_id: Mapped[int] = mapped_column(ForeignKey("floors.id", ondelete="CASCADE"))
    room_code: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(255))
    zone: Mapped[str] = mapped_column(String(100), default="chute-room")
    floor = relationship("Floor", back_populates="rooms")
    devices = relationship("Device", back_populates="room", cascade="all, delete-orphan")
    sensor_events = relationship("SensorEvent", back_populates="room", cascade="all, delete-orphan")
    alerts = relationship("Alert", back_populates="room", cascade="all, delete-orphan")
    ai_events = relationship("AiEvent", back_populates="room", cascade="all, delete-orphan")
    maintenance_logs = relationship("MaintenanceLog", back_populates="room", cascade="all, delete-orphan")

class Device(Base, TimestampMixin):
    __tablename__ = "devices"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    room_id: Mapped[int] = mapped_column(ForeignKey("rooms.id", ondelete="CASCADE"))
    device_id: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    device_type: Mapped[str] = mapped_column(String(50), default="esp32-s3-poe")
    firmware_version: Mapped[str] = mapped_column(String(50), default="1.0.0")
    status: Mapped[str] = mapped_column(String(50), default="online")
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    room = relationship("Room", back_populates="devices")
    sensor_events = relationship("SensorEvent", back_populates="device")

class SimulationNode(Base, TimestampMixin):
    __tablename__ = "simulation_nodes"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    node_id: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    label: Mapped[str] = mapped_column(String(255), default="Simulation Node")
    room_id: Mapped[int | None] = mapped_column(ForeignKey("rooms.id", ondelete="SET NULL"), nullable=True)
    sensor_types: Mapped[list] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(30), default="staged")
    linked_device_id: Mapped[int | None] = mapped_column(ForeignKey("devices.id", ondelete="SET NULL"), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_event_type: Mapped[str | None] = mapped_column(String(80), nullable=True)
    last_payload: Mapped[dict] = mapped_column(JSON, default=dict)
    room = relationship("Room")
    linked_device = relationship("Device")

class SensorEvent(Base, TimestampMixin):
    __tablename__ = "sensor_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    room_id: Mapped[int] = mapped_column(ForeignKey("rooms.id", ondelete="CASCADE"))
    device_id: Mapped[int | None] = mapped_column(ForeignKey("devices.id", ondelete="SET NULL"), nullable=True)
    event_type: Mapped[str] = mapped_column(String(80), index=True)
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    severity: Mapped[str] = mapped_column(String(20), default="info")
    room = relationship("Room", back_populates="sensor_events")
    device = relationship("Device", back_populates="sensor_events")

class Alert(Base, TimestampMixin):
    __tablename__ = "alerts"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    room_id: Mapped[int] = mapped_column(ForeignKey("rooms.id", ondelete="CASCADE"))
    source: Mapped[str] = mapped_column(String(50), default="sensor")
    category: Mapped[str] = mapped_column(String(80))
    message: Mapped[str] = mapped_column(Text)
    severity: Mapped[str] = mapped_column(String(20), default="medium")
    acknowledged: Mapped[bool] = mapped_column(Boolean, default=False)
    acknowledged_by: Mapped[str | None] = mapped_column(String(255), nullable=True)
    acknowledged_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    room = relationship("Room", back_populates="alerts")

class FirmwareVersion(Base, TimestampMixin):
    __tablename__ = "firmware_versions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    version: Mapped[str] = mapped_column(String(50), unique=True)
    build_sha: Mapped[str] = mapped_column(String(80), default="unknown")
    artifact_url: Mapped[str] = mapped_column(String(500))
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    signature: Mapped[str | None] = mapped_column(String(255), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)

class OtaJob(Base, TimestampMixin):
    __tablename__ = "ota_jobs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    target_type: Mapped[str] = mapped_column(String(20), default="room")
    target_ref: Mapped[str] = mapped_column(String(100))
    firmware_version: Mapped[str] = mapped_column(String(50))
    status: Mapped[str] = mapped_column(String(30), default="queued")
    progress: Mapped[int] = mapped_column(Integer, default=0)
    requested_by: Mapped[str] = mapped_column(String(255), default="system")
    logs = relationship("OtaLog", back_populates="ota_job", cascade="all, delete-orphan")

class OtaLog(Base, TimestampMixin):
    __tablename__ = "ota_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ota_job_id: Mapped[int] = mapped_column(ForeignKey("ota_jobs.id", ondelete="CASCADE"))
    room_id: Mapped[int | None] = mapped_column(ForeignKey("rooms.id", ondelete="SET NULL"), nullable=True)
    level: Mapped[str] = mapped_column(String(20), default="info")
    message: Mapped[str] = mapped_column(Text)
    ota_job = relationship("OtaJob", back_populates="logs")
    room = relationship("Room")

class Notification(Base, TimestampMixin):
    __tablename__ = "notifications"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    channel: Mapped[str] = mapped_column(String(30))
    recipient: Mapped[str] = mapped_column(String(255))
    title: Mapped[str] = mapped_column(String(255))
    body: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(30), default="queued")
    meta: Mapped[dict] = mapped_column("metadata", JSON, default=dict)

class AiEvent(Base, TimestampMixin):
    __tablename__ = "ai_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    room_id: Mapped[int] = mapped_column(ForeignKey("rooms.id", ondelete="CASCADE"))
    camera_id: Mapped[str] = mapped_column(String(100), default="camera-unknown")
    event_type: Mapped[str] = mapped_column(String(80), index=True)
    confidence: Mapped[float] = mapped_column(Float, default=0.0)
    snapshot_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    room = relationship("Room", back_populates="ai_events")

class MaintenanceLog(Base, TimestampMixin):
    __tablename__ = "maintenance_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    room_id: Mapped[int] = mapped_column(ForeignKey("rooms.id", ondelete="CASCADE"))
    issue: Mapped[str] = mapped_column(String(255))
    status: Mapped[str] = mapped_column(String(30), default="open")
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    room = relationship("Room", back_populates="maintenance_logs")

class AuditLog(Base, TimestampMixin):
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    actor: Mapped[str] = mapped_column(String(255))
    action: Mapped[str] = mapped_column(String(100))
    entity_type: Mapped[str] = mapped_column(String(80))
    entity_id: Mapped[str] = mapped_column(String(100))
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
