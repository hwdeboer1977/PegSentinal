import "dotenv/config";

export const CONFIG = {
  rpcUrl: process.env.ARB_RPC,
  privateKey: process.env.PRIVATE_KEY,

  hook: process.env.HOOK_ADDRESS,
  vault: process.env.VAULT_ADDRESS,

  chainId: Number(process.env.CHAIN_ID || 1),
  pollSeconds: Number(process.env.POLL_SECONDS || 20),

  targetPrice: Number(process.env.TARGET_PRICE || 1.0),
  depegBps: Number(process.env.DEPEG_BPS || 25),
  cooldownSeconds: Number(process.env.COOLDOWN_SECONDS || 300),
  maxFeeGwei: Number(process.env.MAX_FEE_GWEI || 30),
};