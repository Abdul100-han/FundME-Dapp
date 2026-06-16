import CampaignABI from "@/abis/CampaignABI.json";
import CampaignFactoryABI from "@/abis/CampaignFactoryABI.json";
import type { Abi, Address } from "viem";

export const campaignFactoryAbi = CampaignFactoryABI as Abi;
export const campaignAbi = CampaignABI as Abi;

export const FACTORY_ADDRESS = process.env
  .NEXT_PUBLIC_FACTORY_ADDRESS as Address | undefined;

export const MAX_MILESTONE_PROBE = 32;

export type MilestoneData = {
  id: number;
  description: string;
  amountRequested: bigint;
  votesFor: bigint;
  votesAgainst: bigint;
  votingDeadline: bigint;
  executed: boolean;
};
