from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="Smart Garbage Chute API",
    version="1.0.0"
)

# =========================================================
# CORS
# =========================================================

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# =========================================================
# ROOT
# =========================================================

@app.get("/")
async def root():
    return {
        "status": "running",
        "service": "Smart Garbage Chute Backend"
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy"
    }

# =========================================================
# AUTH
# =========================================================

@app.post("/api/auth/login")
async def login(data: dict):
    email = data.get("email")
    password = data.get("password")

    if (
        email == "admin@alghurair.local"
        and password == "Admin@12345"
    ):
        return {
            "access_token": "demo-token",
            "token_type": "bearer"
        }

    return {
        "error": "Invalid credentials"
    }

# =========================================================
# ANALYTICS
# =========================================================

@app.get("/api/analytics/summary")
async def analytics_summary():
    return {
        "buildings": 3,
        "rooms": 120,
        "devices": 45,
        "alerts_open": 2,
        "alerts_1h": 1,
        "alerts_24h": 7,
        "ai_events_24h": 34,
        "ai_events_1h": 4,
        "ota_jobs_active": 1
    }

# =========================================================
# ALERTS
# =========================================================

@app.get("/api/alerts")
async def alerts(limit: int = 50):
    return [
        {
            "id": 1,
            "severity": "high",
            "category": "fire_detected",
            "message": "Fire detected in chute",
            "room_id": "A-101",
            "acknowledged": False
        },
        {
            "id": 2,
            "severity": "medium",
            "category": "bin_full",
            "message": "Garbage bin nearing capacity",
            "room_id": "B-204",
            "acknowledged": True
        }
    ]

# =========================================================
# DEVICES
# =========================================================

@app.get("/api/devices")
async def devices():
    return [
        {
            "id": 1,
            "device_id": "ESP32-001",
            "room_id": "A-101",
            "device_type": "sensor",
            "firmware_version": "1.0.2",
            "status": "online",
            "last_seen_at": "2026-05-13T10:30:00"
        },
        {
            "id": 2,
            "device_id": "ESP32-002",
            "room_id": "B-204",
            "device_type": "camera",
            "firmware_version": "1.0.5",
            "status": "offline",
            "last_seen_at": "2026-05-13T09:00:00"
        }
    ]

# =========================================================
# ROOMS
# =========================================================

@app.get("/api/rooms")
async def rooms():
    return [
        {
            "id": 1,
            "name": "Room A-101"
        },
        {
            "id": 2,
            "name": "Room B-204"
        }
    ]