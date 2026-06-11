# IICPC Platform — Architecture Blueprint

## Overview
A distributed benchmarking platform that evaluates contestant-submitted exchange/order-book implementations.

## Pipeline
```
Upload → Sandbox → Bot Fleet → Telemetry → Leaderboard
```

## Microservices

| Service | Port | Tech | Purpose |
|---------|------|------|---------|
| sandbox-api | 4000 | Node.js + Express | Code upload, container management |
| bot-coordinator | 3002 | Node.js + KafkaJS | Dispatches bot tasks via Redpanda |
| bot-agent | - | Go | High-concurrency order generator |
| telemetry-ingester | 50051 | Node.js + gRPC | Metrics collection & scoring |
| leaderboard-relay | 3001 | Node.js + Socket.io | Real-time score broadcast |
| leaderboard-frontend | 3000 | Node.js (HTML) | Live dashboard |

## Infrastructure
- **Message Queue**: Redpanda (Kafka-compatible) on port 9092
- **Time-series DB**: TimescaleDB (PostgreSQL) on port 5432
- **Cache/PubSub**: Redis on port 6379
- **Container Runtime**: Docker with resource limits (CPU pinning, memory caps)
- **Orchestration**: Kubernetes (K8s Jobs for bot fleet scaling)

## Isolation Strategy
- Each contestant runs in a separate Docker container
- ReadOnlyRootFilesystem = true
- All Linux capabilities dropped
- no-new-privileges security option
- Isolated network (contestant-net) — no internet access
- CPU: 2 cores max, Memory: 512MB max

## Scoring Formula
```
score = (latency × 0.40) + (throughput × 0.35) + (correctness × 0.25)

latency_score     = max(0, 100 - p99_ms/10)
throughput_score  = min(100, log10(TPS+1) × 30)
correctness_score = (valid_fills / total_fills) × 100
```

## Inter-service Communication
- Bot coordinator → Bot agents: Kafka topic `bot-tasks`
- Bot agents → Telemetry: gRPC `RecordEvent`
- Telemetry → Leaderboard: Redis pub/sub `score-updates`
- Leaderboard relay → Frontend: WebSocket (Socket.io)
