function computeScore({ p99, tps, correctnessRate }) {
  if (!p99 || !tps) return 0;
  // Lower p99 latency = higher latency score
  const latencyScore    = Math.max(0, 100 - (p99 / 10));
  // Higher TPS = higher throughput score (log scale)
  const throughputScore = Math.min(100, Math.log10(tps + 1) * 30);
  // Correctness: did fills respect price-time priority?
  const correctnessScore = (correctnessRate || 0) * 100;
  // Weighted composite
  const score = (
    latencyScore     * 0.40 +
    throughputScore  * 0.35 +
    correctnessScore * 0.25
  );
  return Math.round(score * 100) / 100;
}

module.exports = { computeScore };
