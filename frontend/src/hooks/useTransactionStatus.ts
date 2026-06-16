import { useChainId } from "wagmi";
import { useWaitForTransactionReceipt } from "wagmi";
import type { Hash } from "viem";

import { anvil } from "@/config/chains";

export type TxPhase = "idle" | "pending" | "confirming" | "success" | "error";

export type TransactionStatus = {
  phase: TxPhase;
  hash?: Hash;
  receipt?: ReturnType<typeof useWaitForTransactionReceipt>["data"];
  error: Error | null;
  isLoading: boolean;
  isSuccess: boolean;
  isError: boolean;
  etherscanUrl?: string;
};

export function getEtherscanTxUrl(chainId: number, hash: Hash): string | undefined {
  if (chainId === anvil.id) {
    return undefined;
  }

  if (chainId === 11_155_111) {
    return `https://sepolia.etherscan.io/tx/${hash}`;
  }

  return `https://etherscan.io/tx/${hash}`;
}

type UseTransactionStatusParams = {
  hash?: Hash;
  isWritePending?: boolean;
  writeError?: Error | null;
};

/**
 * Normalizes wagmi write + receipt polling into a single reactive status
 * suitable for toast notifications and loading spinners.
 */
export function useTransactionStatus({
  hash,
  isWritePending = false,
  writeError = null,
}: UseTransactionStatusParams): TransactionStatus {
  const chainId = useChainId();

  const {
    data: receipt,
    isLoading: isConfirming,
    isSuccess: isConfirmed,
    isError: isReceiptError,
    error: receiptError,
  } = useWaitForTransactionReceipt({
    hash,
    query: { enabled: Boolean(hash) },
  });

  const error = writeError ?? receiptError ?? null;

  let phase: TxPhase = "idle";

  if (isWritePending) {
    phase = "pending";
  } else if (writeError || isReceiptError) {
    phase = "error";
  } else if (hash && isConfirming) {
    phase = "confirming";
  } else if (hash && isConfirmed) {
    phase = "success";
  } else if (hash) {
    phase = "confirming";
  }

  const isLoading = isWritePending || phase === "confirming";
  const isSuccess = phase === "success";
  const isError = phase === "error";

  return {
    phase,
    hash,
    receipt,
    error,
    isLoading,
    isSuccess,
    isError,
    etherscanUrl: hash ? getEtherscanTxUrl(chainId, hash) : undefined,
  };
}
