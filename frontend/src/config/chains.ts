import { defineChain } from "viem";
import { sepolia } from "wagmi/chains";

export const anvil = defineChain({
  id: 31_337,
  name: "Anvil",
  nativeCurrency: {
    decimals: 18,
    name: "Ether",
    symbol: "ETH",
  },
  rpcUrls: {
    default: {
      http: ["http://127.0.0.1:8545"],
    },
    public: {
      http: ["http://127.0.0.1:8545"],
    },
  },
});

export const supportedChains = [anvil, sepolia] as const;

export function getChainLabel(chainId: number): string {
  switch (chainId) {
    case anvil.id:
      return "Anvil";
    case sepolia.id:
      return "Sepolia";
    default:
      return `Chain ${chainId}`;
  }
}
