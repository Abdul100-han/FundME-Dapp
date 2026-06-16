"use client";

import { useCallback, useMemo } from "react";
import {
  useReadContract,
  useReadContracts,
  useWriteContract,
} from "wagmi";
import type { Address } from "viem";
import { isAddress } from "viem";

import {
  campaignAbi,
  MAX_MILESTONE_PROBE,
  type MilestoneData,
} from "@/lib/contracts";
import { unwrapReadContractResult } from "@/lib/readContract";
import { useTransactionStatus } from "@/hooks/useTransactionStatus";

export type UseCampaignOptions = {
  campaignAddress?: Address;
};

export type CampaignSummary = {
  creator?: Address;
  targetGoalUsd?: bigint;
  minimumContributionUsd?: bigint;
  duration?: bigint;
  startTime?: bigint;
  fundingDeadline?: bigint;
  totalEthRaised?: bigint;
  totalUsdRaised?: bigint;
  isGoalMet?: boolean;
  hasDeadlinePassed?: boolean;
};

export type FundParams = {
  value: bigint;
};

export type VoteOnMilestoneParams = {
  milestoneId: bigint;
  support: boolean;
};

export type ExecuteMilestoneParams = {
  milestoneId: bigint;
};

export function useCampaign({ campaignAddress }: UseCampaignOptions) {
  const isCampaignConfigured = Boolean(
    campaignAddress && isAddress(campaignAddress),
  );

  const baseReadQuery = {
    enabled: isCampaignConfigured,
  } as const;

  const { data: multicallData, ...multicallQuery } = useReadContracts({
    contracts: [
      {
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "getCreator",
      },
      {
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "getTargetAmountUsd",
      },
      {
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "getMinimumContributionUsd",
      },
      {
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "getDuration",
      },
      {
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "getStartTime",
      },
      {
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "getTotalEthRaised",
      },
      {
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "getTotalUsdRaised",
      },
      {
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "isGoalMet",
      },
      {
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "hasDeadlinePassed",
      },
    ],
    allowFailure: false,
    query: baseReadQuery,
  });

  const milestoneProbeContracts = useMemo(
    () =>
      Array.from({ length: MAX_MILESTONE_PROBE }, (_, index) => ({
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "s_milestones" as const,
        args: [BigInt(index)] as const,
      })),
    [campaignAddress],
  );

  const { data: milestoneProbeData, ...milestoneQuery } = useReadContracts({
    contracts: milestoneProbeContracts,
    allowFailure: true,
    query: baseReadQuery,
  });

  const milestones = useMemo<MilestoneData[]>(() => {
    if (!milestoneProbeData) {
      return [];
    }

    return milestoneProbeData.flatMap((result, index) => {
      if (result.status !== "success" || !result.result) {
        return [];
      }

      const [
        description,
        amountRequested,
        votesFor,
        votesAgainst,
        votingDeadline,
        executed,
      ] = result.result as [
        string,
        bigint,
        bigint,
        bigint,
        bigint,
        boolean,
      ];

      return [
        {
          id: index,
          description,
          amountRequested,
          votesFor,
          votesAgainst,
          votingDeadline,
          executed,
        },
      ];
    });
  }, [milestoneProbeData]);

  const summary = useMemo<CampaignSummary>(() => {
    if (!multicallData) {
      return {};
    }

    const creator = unwrapReadContractResult<Address>(multicallData[0]);
    const targetGoalUsd = unwrapReadContractResult<bigint>(multicallData[1]);
    const minimumContributionUsd = unwrapReadContractResult<bigint>(
      multicallData[2],
    );
    const duration = unwrapReadContractResult<bigint>(multicallData[3]);
    const startTime = unwrapReadContractResult<bigint>(multicallData[4]);
    const totalEthRaised = unwrapReadContractResult<bigint>(multicallData[5]);
    const totalUsdRaised = unwrapReadContractResult<bigint>(multicallData[6]);
    const isGoalMet = unwrapReadContractResult<boolean>(multicallData[7]);
    const hasDeadlinePassed = unwrapReadContractResult<boolean>(
      multicallData[8],
    );

    const fundingDeadline =
      startTime !== undefined && duration !== undefined
        ? startTime + duration
        : undefined;

    return {
      creator,
      targetGoalUsd,
      minimumContributionUsd,
      duration,
      startTime,
      fundingDeadline,
      totalEthRaised,
      totalUsdRaised,
      isGoalMet,
      hasDeadlinePassed,
    };
  }, [multicallData]);

  const isLoadingSummary =
    multicallQuery.isLoading || multicallQuery.isFetching;
  const isLoadingMilestones =
    milestoneQuery.isLoading || milestoneQuery.isFetching;

  const refetchCampaign = useCallback(async () => {
    await Promise.all([multicallQuery.refetch(), milestoneQuery.refetch()]);
  }, [multicallQuery, milestoneQuery]);

  const {
    mutate: submitFund,
    mutateAsync: submitFundAsync,
    data: fundHash,
    isPending: isFundPending,
    error: fundWriteError,
    reset: resetFund,
  } = useWriteContract();

  const {
    mutate: submitVote,
    mutateAsync: submitVoteAsync,
    data: voteHash,
    isPending: isVotePending,
    error: voteWriteError,
    reset: resetVote,
  } = useWriteContract();

  const {
    mutate: submitExecuteMilestone,
    mutateAsync: submitExecuteMilestoneAsync,
    data: executeHash,
    isPending: isExecutePending,
    error: executeWriteError,
    reset: resetExecuteMilestone,
  } = useWriteContract();

  const fundTx = useTransactionStatus({
    hash: fundHash,
    isWritePending: isFundPending,
    writeError: fundWriteError,
  });

  const voteTx = useTransactionStatus({
    hash: voteHash,
    isWritePending: isVotePending,
    writeError: voteWriteError,
  });

  const executeMilestoneTx = useTransactionStatus({
    hash: executeHash,
    isWritePending: isExecutePending,
    writeError: executeWriteError,
  });

  const fund = useCallback(
    ({ value }: FundParams) => {
      if (!campaignAddress || !isAddress(campaignAddress)) {
        throw new Error("Campaign address is not configured.");
      }

      submitFund({
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "fund",
        value,
      });
    },
    [campaignAddress, isCampaignConfigured, submitFund],
  );

  const fundAsync = useCallback(
    async ({ value }: FundParams) => {
      if (!campaignAddress || !isAddress(campaignAddress)) {
        throw new Error("Campaign address is not configured.");
      }

      return submitFundAsync({
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "fund",
        value,
      });
    },
    [campaignAddress, isCampaignConfigured, submitFundAsync],
  );

  const voteOnMilestone = useCallback(
    ({ milestoneId, support }: VoteOnMilestoneParams) => {
      if (!campaignAddress || !isAddress(campaignAddress)) {
        throw new Error("Campaign address is not configured.");
      }

      submitVote({
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "voteOnMilestone",
        args: [milestoneId, support],
      });
    },
    [campaignAddress, isCampaignConfigured, submitVote],
  );

  const voteOnMilestoneAsync = useCallback(
    async ({ milestoneId, support }: VoteOnMilestoneParams) => {
      if (!campaignAddress || !isAddress(campaignAddress)) {
        throw new Error("Campaign address is not configured.");
      }

      return submitVoteAsync({
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "voteOnMilestone",
        args: [milestoneId, support],
      });
    },
    [campaignAddress, isCampaignConfigured, submitVoteAsync],
  );

  const executeMilestone = useCallback(
    ({ milestoneId }: ExecuteMilestoneParams) => {
      if (!campaignAddress || !isAddress(campaignAddress)) {
        throw new Error("Campaign address is not configured.");
      }

      submitExecuteMilestone({
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "executeMilestone",
        args: [milestoneId],
      });
    },
    [campaignAddress, isCampaignConfigured, submitExecuteMilestone],
  );

  const executeMilestoneAsync = useCallback(
    async ({ milestoneId }: ExecuteMilestoneParams) => {
      if (!campaignAddress || !isAddress(campaignAddress)) {
        throw new Error("Campaign address is not configured.");
      }

      return submitExecuteMilestoneAsync({
        address: campaignAddress,
        abi: campaignAbi,
        functionName: "executeMilestone",
        args: [milestoneId],
      });
    },
    [campaignAddress, isCampaignConfigured, submitExecuteMilestoneAsync],
  );

  return {
    campaignAddress,
    isCampaignConfigured,
    summary,
    milestones,
    isLoadingSummary,
    isLoadingMilestones,
    isReadError: multicallQuery.isError || milestoneQuery.isError,
    readError: multicallQuery.error ?? milestoneQuery.error ?? null,
    refetchCampaign,
    fund,
    fundAsync,
    fundTx,
    resetFund,
    voteOnMilestone,
    voteOnMilestoneAsync,
    voteTx,
    resetVote,
    executeMilestone,
    executeMilestoneAsync,
    executeMilestoneTx,
    resetExecuteMilestone,
  };
}
