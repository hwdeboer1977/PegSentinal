// src/math.js
export function tickToPrice(tick) {
  // Same as your frontend tickToPrice() :contentReference[oaicite:3]{index=3}
  return Math.pow(1.0001, tick);
}

export function deviationBpsFromPeg(price, peg = 1.0) {
  // bps, like your deviationBps = (price - 1.0) * 10000 :contentReference[oaicite:4]{index=4}
  return Math.round((price - peg) * 10000);
}
