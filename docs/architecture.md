# Architecture

```mermaid
flowchart LR
  subgraph Building[Multiple buildings]
    subgraph Floor[Multiple floors]
      subgraph Room[Garbage chute room]
        ESP[ESP32-S3 Ethernet PoE Node]
        Sensors[IR / Ultrasonic / Door / Leak / Button]
        Outputs[Buzzer / Light / Relay / PA]
        Cam[PoE IP Camera RTSP/ONVIF]
      end
    end
  end

  ESP -->|MQTT| MQTT[(MQTT Broker)]
  Cam -->|RTSP| AI[AI CCTV Service]
  AI -->|Events| API[FastAPI Backend]
  MQTT --> API
  API --> PG[(PostgreSQL)]
  API --> REDIS[(Redis)]
  API --> WS[WebSocket Gateway]
  WS --> DASH[Next.js Dashboard]
  WS --> MOB[Flutter Mobile App]
  API --> OTA[OTA Service]
  OTA --> FW[Firmware Storage]
  API --> NOTIF[WhatsApp / SMS / Email / BMS]
```

## Key design points
- One controller per room
- VLAN-ready Ethernet topology
- MQTT for sensor telemetry and control
- RTSP AI analytics for image-based misuse detection
- OTA managed centrally with rollback-ready metadata
- Shared room model across dashboard, mobile app, and backend APIs
