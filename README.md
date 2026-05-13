# Smart Garbage Chute Room Monitoring & Detection System

Industrial-style MVP monorepo for multi-building garbage chute monitoring with ESP32 room nodes, RTSP AI analytics, centralized dashboard, OTA management, and cloud-native deployment.

## Included
- FastAPI backend with JWT/RBAC, device registry, alerts, OTA, analytics, websocket updates
- AI CCTV service for RTSP ingestion and simulated YOLO-style detection events
- Next.js + TypeScript dashboard scaffold
- Flutter mobile app scaffold
- ESP32-S3 Ethernet PoE firmware scaffold using ESP-IDF + PlatformIO
- Docker Compose stack with PostgreSQL, Redis, Mosquitto, Nginx, Prometheus, Grafana
- GitHub Actions CI pipeline
- Architecture docs and deployment docs

## Quick start
1. Copy `.env.example` to `.env`
2. Run `docker compose -f infrastructure/docker-compose.yml up --build`
3. Open the dashboard through Nginx

## Demo flow
- Rooms and devices are seeded on startup
- Sensor simulator generates blockage/door/leak events
- AI service emits detections from RTSP or mock frames
- Alerts, OTA jobs, and analytics are visible in the dashboard

## Repo map
See `docs/architecture.md` and `docs/deployment.md`.
