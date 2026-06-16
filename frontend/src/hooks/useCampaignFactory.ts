"use client";

import { useCallback } from "react";
import {
  useReadContract,
  useWriteContract,
} from "wagmi";
import type { Address } from "viem";
import { isAddress } from "viem";

import {
  campaignFactoryAbi,
  FACTORY_ADDRESS,
} from "@/lib/contracts";
import { useTransactionStatus } from "@/hooks/useTransactionStatus";

export type CreateCampaignParams = {
  targetGoalUsd: bigint;
  duration: bigint;
  minContributionUsd: bigint;
  priceFeed: Address;
};

export type UseCampaignFactoryOptions = {
  factoryAddress?: Address;
};

export function useCampaignFactory(options: UseCampaignFactoryOptions = {}) {
  const factoryAddress = options.factoryAddress ?? FACTORY_ADDRESS;
  const isFactoryConfigured = Boolean(factoryAddress && isAddress(factoryAddress));

  const {
    data: deployedCampaigns,
    isLoading: isLoadingCampaigns,
    isFetching: isFetchingCampaigns,
    isError: isCampaignsReadError,
    error: campaignsReadError,
    refetch: refetchCampaigns,
  } = useReadContract({
    address: factoryAddress,
    abi: campaignFactoryAbi,
    functionName: "getDeployedCampaigns",
    query: {
      enabled: isFactoryConfigured,
    },
  });

  const {
    mutate: submitCreateCampaign,
    mutateAsync: submitCreateCampaignAsync,
    data: createCampaignHash,
    isPending: isCreateCampaignPending,
    isError: isCreateCampaignWriteError,
    error: createCampaignWriteError,
    reset: resetCreateCampaign,
  } = useWriteContract();

  const createCampaignTx = useTransactionStatus({
    hash: createCampaignHash,
    isWritePending: isCreateCampaignPending,
    writeError: createCampaignWriteError,
  });

  const createCampaign = useCallback(
    (params: CreateCampaignParams) => {
      if (!factoryAddress || !isAddress(factoryAddress)) {
        throw new Error("Factory address is not configured.");
      }

      submitCreateCampaign({
        address: factoryAddress,
        abi: campaignFactoryAbi,
        functionName: "createCampaign",
        args: [
          params.targetGoalUsd,
          params.duration,
          params.minContributionUsd,
          params.priceFeed,
        ],
      });
    },
    [factoryAddress, isFactoryConfigured, submitCreateCampaign],
  );

  const createCampaignAsync = useCallback(
    async (params: CreateCampaignParams) => {
      if (!factoryAddress || !isAddress(factoryAddress)) {
        throw new Error("Factory address is not configured.");
      }

      return submitCreateCampaignAsync({
        address: factoryAddress,
        abi: campaignFactoryAbi,
        functionName: "createCampaign",
        args: [
          params.targetGoalUsd,
          params.duration,
          params.minContributionUsd,
          params.priceFeed,
        ],
      });
    },
    [factoryAddress, isFactoryConfigured, submitCreateCampaignAsync],
  );

  return {
    factoryAddress,
    isFactoryConfigured,
    deployedCampaigns: deployedCampaigns ?? [],
    isLoadingCampaigns,
    isFetchingCampaigns,
    isCampaignsReadError,
    campaignsReadError,
    refetchCampaigns,
    createCampaign,
    createCampaignAsync,
    createCampaignTx,
    resetCreateCampaign,
    isCreateCampaignWriteError,
  };
}
