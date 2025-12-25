import { ethers } from "ethers";
import { CONFIG } from "./config.js";

export function getProvider() {
  if (!CONFIG.rpcUrl) throw new Error("Missing RPC_URL");
  return new ethers.JsonRpcProvider(CONFIG.rpcUrl, CONFIG.chainId);
}

export function getSigner(provider) {
  if (!CONFIG.privateKey) throw new Error("Missing PRIVATE_KEY");
  return new ethers.Wallet(CONFIG.privateKey, provider);
}
