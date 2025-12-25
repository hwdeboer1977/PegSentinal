// src/decision.js
// Mirrors your frontend "Determine target regime based on current tick" :contentReference[oaicite:5]{index=5}

export function computeTargetRegime({ tick, ranges }) {
  // ranges: { normal, mild, severe } with tickLower/tickUpper/enabled

  if (!ranges?.normal?.enabled) return 0; // fallback

  const normal = ranges.normal;
  const mild = ranges.mild?.enabled ? ranges.mild : null;

  // If tick in Normal range -> Normal
  if (tick >= normal.tickLower && tick <= normal.tickUpper) return 0;

  // Below peg side
  if (tick < normal.tickLower) {
    if (mild && tick >= mild.tickLower) return 1; // Mild
    return 2; // Severe
  }

  // Above peg side (assumes symmetry like your UI logic) :contentReference[oaicite:6]{index=6}
  if (tick > normal.tickUpper) {
    if (mild && tick <= -mild.tickLower) return 1; // Mild
    return 2; // Severe
  }

  return 0;
}
