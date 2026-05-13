# Smart Garbage Chute System - Production Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the Smart Garbage Chute system to production.

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Linux server (Ubuntu 20.04+ recommended)
- Valid SSL certificates or domain for HTTPS
- Configured firewall and security groups
- PostgreSQL backup solution (e.g., Backups to S3)

## Architecture

```
┌─────────────────────────────────────┐
│      Internet/Users                 │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   Nginx (Reverse Proxy, SSL)        │
│   - Load Balancing                  │
│   - SSL Termination                 │
│   - CORS Handling                   │
└──────────┬────────────┬────────┬────┘
           │            │        │
   ┌───────▼──┐  ┌──────▼──┐  ┌─▼──────┐
   │ Frontend  │  │ Backend │  │ AI Svc │
   │ (Next.js) │  │(FastAPI)│  │(RTSP)  │
   └───────┬──┘  └────┬────┘  └────────┘
           │          │
    ┌──────▼──────────▼────────────────┐
    │  Data Layer & Message Queue      │
    │  - PostgreSQL (primary data)     │
    │  - Redis (caching, sessions)     │
    │  - Mosquitto (IoT telemetry)     │
    └─────────────────────────────────┘

    ┌──────────────────────────────────┐
    │  Monitoring Stack                │
    │  - Prometheus (metrics)          │
    │  - Grafana (dashboards)          │
    │  - Alertmanager (routing)        │
    │  - Node Exporter (system)        │
    └──────────────────────────────────┘
```

## Deployment Steps

### 1. Server Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Create deployment directory
sudo mkdir -p /opt/garbage-chute
sudo chown $USER:$USER /opt/garbage-chute
```

### 2. Clone Repository

```bash
cd /opt/garbage-chute
git clone https://github.com/alghurair/smart-garbage-chute-system.git .
```

### 3. Configure Environment Variables

```bash
# Copy example env file
cp .env.example .env

# Edit with production values
nano .env
```

**Key variables to set:**
```env
# Database
DB_USER=postgres
DB_PASSWORD=<strong-password>
DB_HOST=postgres
DB_PORT=5432
DB_NAME=garbage_chute

# Redis
REDIS_URL=redis://redis:6379

# MQTT
MQTT_BROKER_HOST=mosquitto
MQTT_BROKER_PORT=1883

# Backend
SECRET_KEY=<generate-with-openssl>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30

# Frontend
NEXT_PUBLIC_API_URL=https://garbage-chute.yourdomain.com
NEXT_PUBLIC_WS_URL=wss://garbage-chute.yourdomain.com/ws

# AI Service
SIMULATION_MODE=false
MODEL_PATH=/models/yolov8n.pt

# Grafana
GRAFANA_PASSWORD=<strong-password>

# SMTP (for alerts)
SMTP_HOST=smtp.alghurair.local
SMTP_PORT=587
SMTP_USER=alerts@alghurair.local
SMTP_PASSWORD=<password>

# Slack (optional)
SLACK_WEBHOOK_URL=https://hooks.slack.com/...
```

### 4. Setup SSL Certificates

```bash
# Option 1: Using Let's Encrypt
sudo apt install certbot python3-certbot-nginx
sudo certbot certonly --standalone -d garbage-chute.yourdomain.com

# Copy certificates
sudo cp /etc/letsencrypt/live/garbage-chute.yourdomain.com/fullchain.pem \
        infrastructure/nginx/certs/cert.pem
sudo cp /etc/letsencrypt/live/garbage-chute.yourdomain.com/privkey.pem \
        infrastructure/nginx/certs/key.pem

# Set permissions
sudo chown $USER:$USER infrastructure/nginx/certs/*
```

### 5. Initialize Database

```bash
cd /opt/garbage-chute

# Create volumes
docker volume create garbage-chute-postgres

# Start PostgreSQL only
docker-compose up -d postgres
docker-compose exec postgres pg_isready -U postgres

# Run migrations
docker-compose exec backend alembic upgrade head

# Seed initial data
docker-compose exec backend python -c "from app.db.seed import seed; seed()"
```

### 6. Start Services

```bash
# Start all services
docker-compose -f infrastructure/docker-compose.yml up -d

# Verify services
docker-compose ps
```

### 7. Backup Strategy

```bash
# PostgreSQL Backup Script
#!/bin/bash
# /opt/garbage-chute/backup.sh

BACKUP_DIR="/backup/garbage-chute"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Database backup
docker-compose exec -T postgres pg_dump -U postgres garbage_chute > \
  $BACKUP_DIR/db_$DATE.sql

# Compress
gzip $BACKUP_DIR/db_$DATE.sql

# S3 Upload (optional)
# aws s3 cp $BACKUP_DIR/db_$DATE.sql.gz s3://garbage-chute-backups/

# Keep only last 30 days
find $BACKUP_DIR -name "db_*.sql.gz" -mtime +30 -delete

echo "Backup completed: $BACKUP_DIR/db_$DATE.sql.gz"
```

**Setup cron job:**
```bash
crontab -e
# Daily backup at 2 AM
0 2 * * * /opt/garbage-chute/backup.sh
```

### 8. Monitoring Setup

**Access Grafana:**
- URL: https://garbage-chute.yourdomain.com:3001
- Username: admin
- Password: (from .env GRAFANA_PASSWORD)

**Import dashboards:**
- Node Exporter Full: ID 1860
- Docker Container Monitoring: ID 893
- Prometheus: Built-in

### 9. Logging & Log Aggregation

```bash
# View logs
docker-compose logs -f backend
docker-compose logs -f ai-service

# Structured logging to Elasticsearch (optional)
# Install Elasticsearch, Kibana, Filebeat for production logging
```

### 10. Security Hardening

```bash
# Firewall rules
sudo ufw enable
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Disable HTTP access to backend/AI (internal only)
# Keep 8000, 8001 internal to Docker network

# Enable automatic security updates
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

## Health Checks

```bash
# Check Backend
curl -H "Authorization: Bearer <token>" \
     https://garbage-chute.yourdomain.com/api/health

# Check Frontend
curl https://garbage-chute.yourdomain.com

# Check Prometheus
curl https://garbage-chute.yourdomain.com:9090

# Check Grafana
curl https://garbage-chute.yourdomain.com:3001
```

## Scaling & Performance

### Horizontal Scaling

```bash
# Scale backend services
docker-compose up -d --scale backend=3

# Use Nginx load balancing (configured in nginx.conf)
```

### Vertical Scaling

```yaml
# In docker-compose.yml, adjust resource limits:
services:
  backend:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
```

## Troubleshooting

### Service won't start

```bash
# Check logs
docker-compose logs backend

# Check dependencies
docker-compose ps

# Restart service
docker-compose restart backend
```

### High CPU/Memory usage

```bash
# Check resource usage
docker stats

# Check Grafana dashboards for bottlenecks
```

### Database connection failures

```bash
# Check PostgreSQL
docker-compose exec postgres psql -U postgres -d garbage_chute -c "\dt"

# Check Redis
docker-compose exec redis redis-cli ping

# Check MQTT
docker-compose exec mosquitto mosquitto_sub -h mosquitto -t '$SYS/#' -C 1
```

## Maintenance

### Updates

```bash
# Pull latest images
git pull origin main
docker-compose pull

# Rebuild containers
docker-compose build

# Deploy
docker-compose up -d
```

### Database Maintenance

```bash
# VACUUM
docker-compose exec postgres psql -U postgres -d garbage_chute -c "VACUUM FULL ANALYZE"

# Reindex
docker-compose exec postgres psql -U postgres -d garbage_chute -c "REINDEX DATABASE garbage_chute"
```

## Support & Monitoring

- **Status Page**: https://garbage-chute.yourdomain.com/status
- **Logs**: /var/log/garbage-chute/*.log
- **Metrics**: https://garbage-chute.yourdomain.com:9090
- **Alerts**: Slack/Email configured in alertmanager.yml

## References

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Nginx Configuration](https://nginx.org/en/docs/)
- [Prometheus Monitoring](https://prometheus.io/docs/)
- [PostgreSQL Backup](https://www.postgresql.org/docs/current/backup.html)
