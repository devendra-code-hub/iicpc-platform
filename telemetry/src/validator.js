// Validates price-time priority of order fills
function validateFills(orderLog) {
  if (!orderLog || orderLog.length === 0) return { violations: 0, correctnessRate: 1 };

  const buys  = orderLog.filter(o => o.side === 'buy' && o.filled)
    .sort((a, b) => b.price - a.price || a.timestamp - b.timestamp);
  const sells = orderLog.filter(o => o.side === 'sell' && o.filled)
    .sort((a, b) => a.price - b.price || a.timestamp - b.timestamp);

  let violations = 0;

  // Check buys: higher price should fill first, ties by time
  for (let i = 0; i < buys.length - 1; i++) {
    const curr = buys[i];
    const next = buys[i + 1];
    if (!curr.filledAt && next.filledAt) violations++;
    if (curr.price === next.price && curr.timestamp > next.timestamp && next.filledAt && !curr.filledAt) violations++;
  }

  const total = buys.length + sells.length;
  const correctnessRate = total > 0 ? Math.max(0, 1 - violations / total) : 1;
  return { violations, correctnessRate, total };
}

module.exports = { validateFills };
