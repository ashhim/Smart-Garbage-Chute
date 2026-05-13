# Deployment

## Local MVP stack
Run the full demo with Docker Compose:

```bash
docker compose -f infrastructure/docker-compose.yml up --build
```

## Production direction
- Put the backend, AI service, and dashboard behind a managed reverse proxy
- Terminate TLS at Nginx or cloud load balancer
- Store secrets in a secret manager
- Move PostgreSQL to a managed HA cluster
- Move object storage for firmware binaries to S3-compatible storage
- Scale AI workers horizontally by camera count
- Use separate MQTT broker cluster for large estates

## Monitoring
- Prometheus scrapes backend and AI metrics
- Grafana dashboards track alerts, device health, OTA progress, and AI events
- Loki collects container logs
