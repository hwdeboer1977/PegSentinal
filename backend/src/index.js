// src/index.js
import "dotenv/config";
import { ethers } from "ethers";
import { tickToPrice, deviationBpsFromPeg } from "./math.js";
import { getVault, toRangeStruct } from "./vault.js";
import { computeTargetRegime } from "./decision.js";

const StateViewABI = [
  "function getSlot0(bytes32 poolId) view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)",
];

const RPC_URL = process.env.RPC_URL;
const POOL_ID = process.env.POOL_ID;
const STATE_VIEW = process.env.STATE_VIEW_ADDRESS;
const VAULT_ADDRESS = process.env.VAULT_ADDRESS;
const POLL_SECONDS = Number(process.env.POLL_SECONDS || 15);

if (!RPC_URL) throw new Error("Missing RPC_URL");
if (!POOL_ID) throw new Error("Missing POOL_ID");
if (!STATE_VIEW) throw new Error("Missing STATE_VIEW_ADDRESS");
if (!VAULT_ADDRESS) throw new Error("Missing VAULT_ADDRESS");

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function regimeName(n) {
  if (n === 0) return "Normal";
  if (n === 1) return "Mild";
  if (n === 2) return "Severe";
  return `Unknown(${n})`;
}

function boolStr(b) {
  return b ? "yes" : "no";
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);

  const stateView = new ethers.Contract(STATE_VIEW, StateViewABI, provider);
  const vault = getVault(provider, VAULT_ADDRESS);

  console.log("V4 Keeper started (price + regimes)");
  console.log("POOL_ID:", POOL_ID);
  console.log("STATE_VIEW:", STATE_VIEW);
  console.log("VAULT:", VAULT_ADDRESS);

  while (true) {
    try {
      // 1) Pool slot0
      const slot0 = await stateView.getSlot0(POOL_ID);
      const tick = Number(slot0.tick);

      // 2) Price from tick
      const price = tickToPrice(tick);
      const devBps = deviationBpsFromPeg(price, 1.0);

      // 3) Vault regime + ranges
      const [activeRegimeRaw, normalRng, mildRng, severeRng] = await Promise.all([
        vault.activeRegime(),
        vault.normalRange(),
        vault.mildRange(),
        vault.severeRange(),
      ]);

      const activeRegime = Number(activeRegimeRaw);

      const ranges = {
        normal: toRangeStruct(normalRng),
        mild: toRangeStruct(mildRng),
        severe: toRangeStruct(severeRng),
      };

      // 4) Decide target regime (same logic as your UI)
      const targetRegime = computeTargetRegime({ tick, ranges });

      // 5) Derived flags
      const needsRegimeUpdate = targetRegime !== activeRegime;

      const inNormal =
        tick >= ranges.normal.tickLower && tick <= ranges.normal.tickUpper;

      const inMild =
        ranges.mild.enabled &&
        tick >= ranges.mild.tickLower &&
        tick <= ranges.mild.tickUpper;

      const inSevere =
        ranges.severe.enabled &&
        tick >= ranges.severe.tickLower &&
        tick <= ranges.severe.tickUpper;

      console.log(
        `[${new Date().toISOString()}] tick=${tick} price=${price.toFixed(6)} dev=${(devBps / 100).toFixed(2)}% ` +
          `active=${regimeName(activeRegime)} target=${regimeName(targetRegime)} needsUpdate=${boolStr(needsRegimeUpdate)} ` +
          `normal=[${ranges.normal.tickLower},${ranges.normal.tickUpper}] enabled=${boolStr(ranges.normal.enabled)} in=${boolStr(inNormal)} ` +
          `mild=[${ranges.mild.tickLower},${ranges.mild.tickUpper}] enabled=${boolStr(ranges.mild.enabled)} in=${boolStr(inMild)} ` +
          `severe=[${ranges.severe.tickLower},${ranges.severe.tickUpper}] enabled=${boolStr(ranges.severe.enabled)} in=${boolStr(inSevere)}`
      );
    } catch (err) {
      console.error("Loop error:", err?.reason || err?.message || err);
    }

    await sleep(POLL_SECONDS * 1000);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
