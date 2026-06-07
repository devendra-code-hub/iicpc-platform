# IICPC Summer Hackathon 2026 — Distributed Benchmarking Platform

## Architecture
- **sandbox/**: Submission API + Docker container isolation
- **bot-fleet/**: Distributed load generator (Go bots + Kafka)
- **telemetry/**: gRPC ingester + TimescaleDB + scoring engine
- **leaderboard/**: React frontend + Socket.io relay
- **infra/**: Terraform, Kubernetes manifests, CI pipeline
- **docs/**: Architecture blueprint, API reference, scoring formula

## Quick Start
```bash
docker-compose up -d
```

 
