# IICPC Summer Hackathon 2026 — Distributed Benchmarking Platform

## Team
- Devendra Kumar Mahto

## Live Demo
- Sandbox API: http://localhost:4000
- Leaderboard: http://localhost:3000

## Architecture 
-Upload → Sandbox (Docker) → Bot Fleet (Go+Kafka) → Telemetry (gRPC+TimescaleDB) → Leaderboard (Socket.io)

## Components Built
- **Submission & Sandboxing Engine** — Node.js + Dockerode, strict resource limits (CPU pinning, 512MB memory cap, no-new-privileges, dropped capabilities)
- **Distributed Bot Fleet** — Go goroutines (1000+ concurrent bots), Redpanda/Kafka task distribution, K8s Job scaling
- **Telemetry & Validation Ingester** — gRPC server, TimescaleDB hypertable, p50/p90/p99 latency, TPS, correctness scoring
- **Real-Time Leaderboard** — Socket.io WebSocket relay, Redis pub/sub, live score updates

## Scoring Formula score = (latency × 0.40) + (throughput × 0.35) + (correctness × 0.25) ## Quick Start
```bash
docker compose up -d
curl http://localhost:4000/health
```

## IaC
- Terraform EKS cluster in `/infra/terraform/`
- Kubernetes manifests in `/infra/k8s/manifests/`
- GitHub Actions CI in `/infra/ci/pipeline.yml`

## Tech Stack
Docker · Node.js · Go · Redpanda · TimescaleDB · Redis · gRPC · Socket.io · Terraform · Kubernetes
