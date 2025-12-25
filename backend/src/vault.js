// src/vault.js
import { ethers } from "ethers";

export const VaultABI = [
  "function activeRegime() view returns (uint8)",
  "function normalRange() view returns (int24 tickLower, int24 tickUpper, bool enabled)",
  "function mildRange() view returns (int24 tickLower, int24 tickUpper, bool enabled)",
  "function severeRange() view returns (int24 tickLower, int24 tickUpper, bool enabled)",
];

export function getVault(provider, vaultAddress) {
  return new ethers.Contract(vaultAddress, VaultABI, provider);
}

export function toRangeStruct(rangeTuple) {
  return {
    tickLower: Number(rangeTuple[0]),
    tickUpper: Number(rangeTuple[1]),
    enabled: Boolean(rangeTuple[2]),
  };
}
