# API overview

Base URL: `/api`

## Auth
- `POST /auth/login`
- `GET /auth/me`

## Buildings
- `GET /buildings`
- `POST /buildings`
- `GET /buildings/{id}`

## Rooms and devices
- `GET /rooms`
- `POST /rooms`
- `GET /devices`
- `POST /devices/{id}/command`

## Alerts
- `GET /alerts`
- `POST /alerts/{id}/ack`

## OTA
- `GET /ota/jobs`
- `POST /ota/jobs`
- `GET /ota/jobs/{id}`

## Analytics
- `GET /analytics/summary`
- `GET /events`
