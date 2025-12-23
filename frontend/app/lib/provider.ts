import { JsonRpcProvider } from "ethers";

let providerInstance: JsonRpcProvider | null = null;

export function getProvider(): JsonRpcProvider {
  if (!providerInstance) {
    const rpcUrl = process.env.NEXT_PUBLIC_RPC_URL || "http://127.0.0.1:8545";
    providerInstance = new JsonRpcProvider(rpcUrl);
  }
  return providerInstance;
}

// Reset provider (useful for testing or switching networks)
export function resetProvider(): void {
  providerInstance = null;
}
