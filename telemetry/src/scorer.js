 
function computeScore({ p50, p90, p99, tps, correctnessRate }) {
 
  const latencyScore = Math.max(0, 100 - (p99 / 10));

 
  const throughputScore = Math.min(100, Math.log10(tps + 1) * 30);

 
  const correctnessScore = correctnessRate * 100;

  
  return (
    latencyScore    * 0.40 +
    throughputScore * 0.35 +
    correctnessScore * 0.25
  ).toFixed(2);
}

module.exports = { computeScore };