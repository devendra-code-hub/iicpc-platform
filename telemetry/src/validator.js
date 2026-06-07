 
function validateFills(orderLog) {
  const buys  = orderLog.filter(o => o.side === 'buy').sort((a, b) => b.price - a.price || a.ts - b.ts);
  const sells = orderLog.filter(o => o.side === 'sell').sort((a, b) => a.price - b.price || a.ts - b.ts);

  let violations = 0;
 
  buys.forEach((buy, i) => {
    if (buy.filledAt && buys[i + 1] && !buys[i + 1].filledAt) {
      
      if (buys[i + 1].price >= buy.price) violations++;
    }
  });

  return { violations, correctnessRate: 1 - violations / orderLog.length };
}