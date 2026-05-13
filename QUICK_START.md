# 🚀 Quick Start Guide - Smart Garbage Chute System

## 5-Minute Quick Start

### 1. Clone & Setup

```bash
# Clone repository
git clone https://github.com/alghurair/smart-garbage-chute-system.git
cd smart-garbage-chute-system

# Copy environment template
cp .env.example .env

# Edit for your environment (optional for local dev)
nano .env
```

### 2. Start All Services

```bash
cd infrastructure

# Start Docker Compose stack
docker-compose up -d

# Wait for services to initialize (~30 seconds)
docker-compose ps
```

### 3. Access Services

| Service | URL | Credentials |
|---------|-----|-------------|
| **Web Dashboard** | http://localhost | admin@alghurair.local / password123 |
| **API Docs** | http://localhost:8000/docs | (Swagger UI) |
| **Grafana** | http://localhost:3001 | admin / admin |
| **Prometheus** | http://localhost:9090 | (no auth) |

### 4. Test the System

```bash
# 1. Login to dashboard
# Open http://localhost in browser
# Login with admin@alghurair.local / password123

# 2. Simulate MQTT telemetry (from another terminal)
docker-compose exec mosquitto mosquitto_pub \
  -t "garbage/telemetry/CHR_01" \
  -m '{
    "room_id": 1,
    "door_open": false,
    "blockage": true,
    "leak_detected": false,
    "motion_detected": true,
    "ultrasonic_distance_cm": 8.5,
    "temperature": 28.3,
    "humidity": 65,
    "uptime_sec": 3600
  }'

# 3. Watch alert appear in dashboard (real-time WebSocket)
# 4. Check backend logs
docker-compose logs -f backend

# 5. Monitor in Prometheus
# Visit http://localhost:9090/graph
# Query: up{job="backend"}
```

---

## Development Workflow

### Backend Development

```bash
# 1. Enter backend container
docker-compose exec backend bash

# 2. Run tests
pytest tests/ --cov=app

# 3. Check code style
flake8 app/

# 4. Type checking
mypy app/

# 5. Apply migrations
alembic upgrade head

# 6. Create new migration
alembic revision --autogenerate -m "Add field X"
```

### Frontend Development

```bash
# 1. Start Next.js dev server (local machine, not Docker)
cd frontend
npm install
npm run dev

# 2. Open http://localhost:3000

# 3. Format code
npm run lint

# 4. Build for production
npm run build
npm start
```

### Mobile App Development

```bash
# 1. Install Flutter
curl https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.16.0-stable.zip
# (or download for your OS)

# 2. Navigate to mobile app
cd mobile

# 3. Get dependencies
flutter pub get

# 4. Run on emulator
flutter run -d emulator-5554

# 5. Run tests
flutter test
```

### Firmware Development

```bash
# 1. Install PlatformIO
pip install platformio

# 2. Open project
cd firmware
platformio init --project-type esp

# 3. Build firmware
platformio run --environment esp32-s3-poe

# 4. Upload to board
platformio run --target upload --environment esp32-s3-poe

# 5. Monitor serial output
platformio device monitor
```

---

## Common Tasks

### Restart Services

```bash
# Restart specific service
docker-compose restart backend

# Restart all services
docker-compose restart

# View logs
docker-compose logs -f backend  # Last 100 lines, follow
docker-compose logs backend --tail=50
```

### View Database

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U postgres -d garbage_chute

# List tables
\dt

# Query alerts
SELECT id, severity, message, created_at FROM alerts ORDER BY created_at DESC LIMIT 10;

# Exit
\q
```

### View MQTT Broker

```bash
# Subscribe to telemetry topic
docker-compose exec mosquitto mosquitto_sub -t "garbage/telemetry/#" -v

# Publish test message
docker-compose exec mosquitto mosquitto_pub -t "garbage/room/CHR_01/cmd/buzzer" -m "on"
```

### Check Redis Cache

```bash
# Connect to Redis
docker-compose exec redis redis-cli

# View all keys
KEYS *

# Get session data
GET session:abc123

# Clear all
FLUSHALL

# Exit
EXIT
```

### Monitor System Performance

```bash
# Docker stats
docker stats

# Prometheus query interface
# http://localhost:9090

# Grafana dashboards
# http://localhost:3001

# Check backend metrics
curl http://localhost:8000/metrics
```

---

## Troubleshooting

### Services Won't Start

```bash
# Check logs
docker-compose logs

# Rebuild containers
docker-compose build --no-cache

# Full reset
docker-compose down -v  # WARNING: Deletes all data!
docker-compose up -d
```

### Database Connection Error

```bash
# Check PostgreSQL health
docker-compose exec postgres pg_isready -U postgres

# Check connection from backend
docker-compose logs backend | grep -i "connection\|error"

# Verify environment variables
cat .env | grep DATABASE_URL

# Run migrations
docker-compose exec backend alembic upgrade head
```

### MQTT Not Working

```bash
# Check broker is running
docker-compose ps mosquitto

# Test connection
docker-compose exec mosquitto mosquitto_sub -t '$SYS/#' -C 1

# Check backend MQTT logs
docker-compose logs backend | grep -i mqtt

# Verify backend can reach broker
docker-compose exec backend ping mosquitto
```

### High Memory Usage

```bash
# Check top processes
docker stats

# Check database connections
docker-compose exec postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Check Redis memory
docker-compose exec redis redis-cli INFO memory

# Clear Redis cache
docker-compose exec redis redis-cli FLUSHALL
```

### API Endpoint Not Responding

```bash
# Test backend directly
curl http://localhost:8000/health

# Check backend logs
docker-compose logs backend -f

# Restart backend
docker-compose restart backend

# Check if port is in use
lsof -i :8000
```

---

## Architecture Overview

```
┌─────────────────────────────────────┐
│         User Applications            │
│  Web | Mobile | Dashboard            │
└────────────────┬────────────────────┘
                 │
       ┌─────────▼─────────┐
       │   Nginx (Proxy)   │
       │   Port 80/443     │
       └─────────┬─────────┘
                 │
    ┌────────────┼────────────┐
    ▼            ▼            ▼
┌────────┐  ┌────────┐  ┌───────────┐
│Backend │  │Frontend│  │ AI Service│
│:8000   │  │:3000   │  │  :8001    │
└────┬───┘  └────────┘  └───────────┘
     │
┌────┴────────┬──────────┬───────────┐
▼             ▼          ▼           ▼
PostgreSQL  Redis    Mosquitto   (Files)
:5432      :6379      :1883

Monitoring Stack:
Prometheus :9090
Grafana    :3001
```

---

## API Examples

### Login & Get Token

```bash
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@alghurair.local",
    "password": "password123"
  }'

# Response:
# {
#   "access_token": "eyJhbGc...",
#   "token_type": "bearer"
# }

# Save token
TOKEN="eyJhbGc..."
```

### Get Dashboard Summary

```bash
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/analytics/summary

# Response:
# {
#   "buildings": 2,
#   "floors": 5,
#   "rooms": 42,
#   "devices": 50,
#   "alerts_open": 3,
#   "alerts_24h": 15,
#   "ai_events_24h": 8,
#   "ota_jobs_active": 0,
#   "devices_online": 48,
#   "devices_offline": 2
# }
```

### List Alerts

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/alerts?limit=10&offset=0"

# Response:
# {
#   "items": [
#     {
#       "id": 1,
#       "severity": "high",
#       "category": "blockage",
#       "message": "Blockage detected in room CHR_01",
#       "acknowledged": false,
#       "created_at": "2024-01-15T10:30:00Z"
#     },
#     ...
#   ],
#   "total": 45
# }
```

### Acknowledge Alert

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/alerts/1/acknowledge

# Response:
# {
#   "id": 1,
#   "acknowledged": true,
#   "acknowledged_at": "2024-01-15T11:00:00Z",
#   "acknowledged_by": "admin@alghurair.local"
# }
```

### WebSocket Connection

```bash
# Using websocat tool
websocat "ws://localhost:8000/ws?token=$TOKEN"

# Or in JavaScript
const ws = new WebSocket(`ws://localhost:8000/ws?token=${TOKEN}`);
ws.onmessage = (event) => {
  console.log('Message:', JSON.parse(event.data));
};
```

---

## Production Deployment

### Quick Production Setup

```bash
# 1. Update .env with production values
nano .env
# Set: ENVIRONMENT=production, SSL_ENABLED=true, etc.

# 2. Generate SSL certificates
certbot certonly --standalone -d garbage-chute.yourdomain.com

# 3. Copy certificates
cp /etc/letsencrypt/live/garbage-chute.yourdomain.com/fullchain.pem \
   infrastructure/nginx/certs/cert.pem
cp /etc/letsencrypt/live/garbage-chute.yourdomain.com/privkey.pem \
   infrastructure/nginx/certs/key.pem

# 4. Deploy
docker-compose -f infrastructure/docker-compose.yml up -d

# 5. Verify
curl https://garbage-chute.yourdomain.com/health
```

### Backup Database

```bash
# Manual backup
docker-compose exec postgres pg_dump -U postgres garbage_chute > backup.sql
gzip backup.sql

# Restore from backup
gunzip backup.sql.gz
docker-compose exec -T postgres psql -U postgres garbage_chute < backup.sql
```

### View System Metrics

```bash
# CPU & Memory
docker stats

# HTTP requests (Prometheus)
curl "http://localhost:9090/api/v1/query?query=rate(http_requests_total%5B5m%5D)"

# Alert statistics
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/analytics/alerts-stats?hours=24"
```

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `.env` | Environment configuration |
| `docker-compose.yml` | Service orchestration |
| `backend/app/main.py` | Backend entry point |
| `frontend/app/page.jsx` | Frontend dashboard |
| `mobile/lib/main.dart` | Mobile app entry |
| `firmware/main/main.cpp` | ESP32 firmware |
| `infrastructure/nginx/nginx.conf` | Reverse proxy config |
| `DEPLOYMENT.md` | Production deployment |
| `SYSTEM_COMPLETION_REPORT.md` | Full documentation |

---

## Emergency Procedures

### System Down

```bash
# 1. Check service status
docker-compose ps

# 2. Check logs
docker-compose logs | grep ERROR

# 3. Restart all services
docker-compose down
docker-compose up -d

# 4. Verify health
curl http://localhost:8000/health
```

### Data Recovery

```bash
# From latest backup
docker-compose down

# Restore database
gunzip latest_backup.sql.gz
docker-compose up -d postgres
docker-compose exec -T postgres psql -U postgres garbage_chute < latest_backup.sql

# Restart other services
docker-compose up -d
```

### Database Corruption

```bash
# 1. Backup current (broken) database
docker-compose exec postgres pg_dump -U postgres garbage_chute > broken_backup.sql

# 2. Drop and recreate
docker-compose exec postgres psql -U postgres -c "DROP DATABASE garbage_chute;"
docker-compose exec postgres psql -U postgres -c "CREATE DATABASE garbage_chute;"

# 3. Apply migrations
docker-compose exec backend alembic upgrade head

# 4. Restore from clean backup
docker-compose exec -T postgres psql -U postgres garbage_chute < clean_backup.sql
```

---

## Performance Tuning

### Increase PostgreSQL Connection Pool

```env
# .env
DATABASE_URL=postgresql+asyncpg://user:pass@postgres/db?min_size=10&max_size=20
```

### Increase Redis Cache

```yaml
# docker-compose.yml
redis:
  command: redis-server --maxmemory 2gb --maxmemory-policy allkeys-lru
```

### Optimize Prometheus Retention

```yaml
# docker-compose.yml
prometheus:
  command:
    - '--storage.tsdb.retention.time=30d'
    - '--query.max-samples=10000000'
```

---

## Next Steps

1. **Review** [SYSTEM_COMPLETION_REPORT.md](SYSTEM_COMPLETION_REPORT.md) for full architecture
2. **Deploy** using [DEPLOYMENT.md](DEPLOYMENT.md) for production
3. **Monitor** via Grafana dashboard at http://localhost:3001
4. **Configure** Firebase for mobile push notifications
5. **Setup** email/SMS providers for alerts
6. **Test** with real ESP32 hardware

---

**Happy monitoring! 🎉**

For support: support@alghurair.local  
Documentation: [GitHub Wiki](https://github.com/alghurair/smart-garbage-chute-system/wiki)  
Issues: [GitHub Issues](https://github.com/alghurair/smart-garbage-chute-system/issues)
