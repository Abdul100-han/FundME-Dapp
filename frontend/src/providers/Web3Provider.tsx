"use client";

import "@rainbow-me/rainbowkit/styles.css";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { getDefaultConfig, RainbowKitProvider } from "@rainbow-me/rainbowkit";
import { ReactNode, useState } from "react";
import { fallback, http, WagmiProvider } from "wagmi";

import { anvil, supportedChains } from "@/config/chains";

const walletConnectProjectId =
  process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "";

const sepoliaRpcPrimary =
  process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL ?? "https://rpc.sepolia.org";

const sepoliaRpcFallback =
  process.env.NEXT_PUBLIC_SEPOLIA_RPC_FALLBACK_URL ??
  "https://ethereum-sepolia.publicnode.com";

export const wagmiConfig = getDefaultConfig({
  appName: "FundMe DApp",
  projectId:
    walletConnectProjectId.length > 0
      ? walletConnectProjectId
      : "00000000000000000000000000000000",
  chains: supportedChains,
  ssr: true,
  transports: {
    [anvil.id]: fallback([
      http("http://127.0.0.1:8545"),
      http("http://localhost:8545"),
    ]),
    [supportedChains[1].id]: fallback([
      http(sepoliaRpcPrimary),
      http(sepoliaRpcFallback),
    ]),
  },
});

type Web3ProviderProps = {
  children: ReactNode;
};

export function Web3Provider({ children }: Web3ProviderProps) {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider>{children}</RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
