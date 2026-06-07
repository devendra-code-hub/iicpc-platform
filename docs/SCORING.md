# Scoring Formula

Composite score (0–100):

```
score = (latencyScore × 0.40) + (throughputScore × 0.35) + (correctnessScore × 0.25)
```

- **Latency score** = max(0, 100 - p99_ms / 10)
- **Throughput score** = min(100, log10(TPS + 1) × 30)
- **Correctness score** = (valid_fills / total_fills) × 100

Correctness validates price-time priority: best price fills first,
ties broken by order arrival timestamp.
