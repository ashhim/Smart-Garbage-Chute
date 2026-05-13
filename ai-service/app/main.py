from contextlib import asynccontextmanager
from datetime import datetime, timezone
import asyncio
import logging
import random
import json
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
import httpx

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

# ============================================================
# CONFIGURATION
# ============================================================
BACKEND_URL = "http://backend:8000"
AI_MODEL = "yolov8n"  # Could be yolov8n, yolov8s, yolov8m, etc.
CONFIDENCE_THRESHOLD = 0.5
RTSP_CONNECTION_TIMEOUT = 10
RTSP_READ_TIMEOUT = 30
SNAPSHOT_DIR = Path("/tmp/snapshots")
SNAPSHOT_DIR.mkdir(exist_ok=True)

# Simulation mode toggle
SIMULATION_MODE = True

# ============================================================
# MODELS
# ============================================================

class RtspRequest(BaseModel):
    room_id: str
    camera_id: str
    rtsp_url: Optional[str] = None

class AiEvent(BaseModel):
    room_id: str
    camera_id: str
    event_type: str
    confidence: float
    snapshot_url: Optional[str] = None
    timestamp: int
    payload: dict

class DetectionResult(BaseModel):
    room_id: str
    camera_id: str
    event_type: str
    confidence: float
    snapshot_url: Optional[str] = None

# ============================================================
# AI MODEL LOADER (Stub - implement YOLOv8 loading here)
# ============================================================

class YOLOv8Detector:
    """YOLO v8 object detector wrapper."""
    
    def __init__(self, model_name: str = AI_MODEL):
        self.model_name = model_name
        self.model = None
        logger.info(f"YOLOv8Detector initialized with model: {model_name}")
        # TODO: Lazy load model: self.model = torch.hub.load(...) or similar
    
    async def detect_frame(self, frame):
        """Run inference on frame and return detections."""
        try:
            # TODO: Implement actual YOLOv8 inference
            # This is where you'd call: results = self.model(frame)
            # For now, return mock detections
            if SIMULATION_MODE:
                return await self._mock_detect(frame)
            else:
                raise NotImplementedError("Real YOLOv8 inference not yet implemented")
        except Exception as e:
            logger.exception(f"Detection failed: {e}")
            return []
    
    async def _mock_detect(self, frame):
        """Mock detection for MVP testing."""
        # Simulate occasional garbage detection
        if random.random() > 0.85:  # 15% chance of garbage
            return [
                {
                    "class": "garbage",
                    "confidence": round(random.uniform(0.70, 0.99), 2),
                    "bbox": [10, 20, 100, 150]
                }
            ]
        return []

# ============================================================
# RTSP STREAM HANDLER (Stub)
# ============================================================

class RtspStreamHandler:
    """RTSP stream ingestion and frame extraction."""
    
    async def get_frame(self, rtsp_url: str, timeout: int = RTSP_READ_TIMEOUT):
        """Fetch a single frame from RTSP stream."""
        try:
            # TODO: Implement actual RTSP frame capture using OpenCV
            # cv2.VideoCapture(rtsp_url) for real implementation
            if SIMULATION_MODE:
                return await self._mock_frame()
            else:
                raise NotImplementedError("Real RTSP stream capture not yet implemented")
        except asyncio.TimeoutError:
            logger.error(f"RTSP stream timeout: {rtsp_url}")
            return None
        except Exception as e:
            logger.exception(f"RTSP stream error: {e}")
            return None
    
    async def _mock_frame(self):
        """Return mock frame for simulation mode."""
        # In production, this would be a numpy array (BGR image)
        return {"width": 1920, "height": 1080, "channels": 3}

# ============================================================
# DETECTION PIPELINE
# ============================================================

class DetectionPipeline:
    """Main AI detection pipeline orchestrator."""
    
    def __init__(self):
        self.detector = YOLOv8Detector()
        self.stream_handler = RtspStreamHandler()
        self.detection_history = {}  # Track recent detections to avoid spam
        self.max_history_size = 100
    
    async def process_rtsp_stream(self, room_id: str, camera_id: str, rtsp_url: str):
        """Continuous RTSP stream processing."""
        logger.info(f"Processing RTSP stream: {rtsp_url} for room {room_id}")
        
        while True:
            try:
                # Get frame from stream
                frame = await self.stream_handler.get_frame(rtsp_url)
                if not frame:
                    await asyncio.sleep(5)
                    continue
                
                # Run detection
                detections = await self.detector.detect_frame(frame)
                
                # Process detections
                for det in detections:
                    event = await self._process_detection(room_id, camera_id, det)
                    if event:
                        # Publish to backend
                        await self._publish_event(event)
                
                # Sleep before next frame
                await asyncio.sleep(2)  # Process 0.5 FPS for efficiency
                
            except asyncio.CancelledError:
                logger.info(f"RTSP stream processing cancelled for {room_id}")
                break
            except Exception as e:
                logger.exception(f"Error processing stream for {room_id}: {e}")
                await asyncio.sleep(5)
    
    async def _process_detection(self, room_id: str, camera_id: str, detection: dict):
        """Process a single detection result."""
        event_type = detection.get("class", "unknown")
        confidence = detection.get("confidence", 0.0)
        
        if confidence < CONFIDENCE_THRESHOLD:
            return None
        
        # Map detection class to event type
        event_type = self._map_detection_to_event(event_type)
        
        # De-duplicate: Skip if same event in last 30 seconds
        key = f"{room_id}_{event_type}"
        now = datetime.now(timezone.utc).timestamp()
        if key in self.detection_history:
            if now - self.detection_history[key] < 30:
                logger.debug(f"De-duplicating event: {event_type}")
                return None
        
        self.detection_history[key] = now
        
        # Create event
        event = AiEvent(
            room_id=room_id,
            camera_id=camera_id,
            event_type=event_type,
            confidence=confidence,
            snapshot_url=None,  # TODO: Save snapshot
            timestamp=int(now),
            payload={
                "model": AI_MODEL,
                "bbox": detection.get("bbox"),
                "threshold": CONFIDENCE_THRESHOLD
            }
        )
        
        logger.info(f"Detection: {event_type} (confidence: {confidence})")
        return event
    
    def _map_detection_to_event(self, class_name: str) -> str:
        """Map YOLOv8 detection class to alert event type."""
        mapping = {
            "garbage": "garbage_on_floor",
            "person": "misuse",
            "overflow": "overflow",
            "leakage": "leak",
        }
        return mapping.get(class_name.lower(), class_name)
    
    async def _publish_event(self, event: AiEvent):
        """Publish AI event to backend."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.post(
                    f"{BACKEND_URL}/api/ai-events",
                    json=event.model_dump()
                )
                if response.status_code == 201:
                    logger.info(f"AI event published: {event.event_type}")
                else:
                    logger.warning(f"Failed to publish AI event: {response.status_code}")
        except Exception as e:
            logger.exception(f"Error publishing AI event: {e}")

# ============================================================
# GLOBAL INSTANCES
# ============================================================

pipeline = DetectionPipeline()
active_streams = {}  # room_id -> asyncio.Task mapping

# ============================================================
# LIFESPAN MANAGEMENT
# ============================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application startup and shutdown."""
    logger.info("AI Service starting up")
    yield
    logger.info("AI Service shutting down")
    # Cancel all active streams
    for room_id, task in active_streams.items():
        logger.info(f"Cancelling stream for {room_id}")
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass

# ============================================================
# FASTAPI APPLICATION
# ============================================================

app = FastAPI(
    title="Smart Garbage Chute AI Service",
    version="1.0.0",
    description="RTSP-based AI detection service for garbage chute monitoring",
    lifespan=lifespan
)

# ============================================================
# ENDPOINTS
# ============================================================

@app.get("/health")
async def health():
    """Health check endpoint."""
    return {
        "status": "ok",
        "service": "ai-detection",
        "model": AI_MODEL,
        "active_streams": len(active_streams),
        "simulation_mode": SIMULATION_MODE
    }

@app.post("/start-stream")
async def start_stream(req: RtspRequest):
    """Start processing RTSP stream for a room."""
    try:
        room_id = req.room_id
        
        if room_id in active_streams:
            return {
                "status": "already_running",
                "room_id": room_id,
                "message": f"Stream for {room_id} is already running"
            }
        
        # Create processing task
        task = asyncio.create_task(
            pipeline.process_rtsp_stream(req.room_id, req.camera_id, req.rtsp_url or "mock")
        )
        active_streams[room_id] = task
        
        logger.info(f"Started stream processing for {room_id}")
        return {
            "status": "started",
            "room_id": room_id,
            "camera_id": req.camera_id,
            "rtsp_url": req.rtsp_url
        }
    except Exception as e:
        logger.exception(f"Error starting stream: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/stop-stream")
async def stop_stream(room_id: str):
    """Stop processing RTSP stream for a room."""
    try:
        if room_id not in active_streams:
            return {
                "status": "not_running",
                "room_id": room_id,
                "message": f"No stream found for {room_id}"
            }
        
        task = active_streams[room_id]
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
        
        del active_streams[room_id]
        logger.info(f"Stopped stream for {room_id}")
        
        return {
            "status": "stopped",
            "room_id": room_id
        }
    except Exception as e:
        logger.exception(f"Error stopping stream: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/infer", response_model=AiEvent)
async def infer(req: RtspRequest):
    """Perform one-shot inference on RTSP stream."""
    try:
        # Get frame from stream
        frame = await pipeline.stream_handler.get_frame(req.rtsp_url or "mock")
        if not frame:
            raise HTTPException(status_code=502, detail="Failed to get frame from RTSP stream")
        
        # Run detection
        detections = await pipeline.detector.detect_frame(frame)
        
        if not detections:
            # No objects detected
            event_type = "normal"
            confidence = 1.0
        else:
            det = detections[0]  # Use highest confidence detection
            event_type = pipeline._map_detection_to_event(det.get("class", "unknown"))
            confidence = det.get("confidence", 0.0)
        
        return AiEvent(
            room_id=req.room_id,
            camera_id=req.camera_id,
            event_type=event_type,
            confidence=confidence,
            snapshot_url=None,
            timestamp=int(datetime.now(timezone.utc).timestamp()),
            payload={"source": AI_MODEL, "rtsp": bool(req.rtsp_url)}
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"Inference error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/streams")
async def list_streams():
    """List active RTSP streams."""
    return {
        "count": len(active_streams),
        "streams": list(active_streams.keys())
    }

@app.get("/stats")
async def get_stats():
    """Get AI service statistics."""
    return {
        "model": AI_MODEL,
        "confidence_threshold": CONFIDENCE_THRESHOLD,
        "active_streams": len(active_streams),
        "simulation_mode": SIMULATION_MODE,
        "detection_history_size": len(pipeline.detection_history),
        "uptime_seconds": int(datetime.now(timezone.utc).timestamp())
    }
