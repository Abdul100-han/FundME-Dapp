export default function Home() {
  return (
    <div className="flex flex-1 flex-col">
      <section className="mx-auto flex w-full max-w-6xl flex-1 flex-col justify-center px-4 py-16 sm:px-6 lg:px-8">
        <div className="max-w-2xl">
          <p className="mb-3 text-sm font-medium uppercase tracking-wider text-indigo-600 dark:text-indigo-400">
            Milestone Crowdfunding
          </p>
          <h1 className="text-4xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-50 sm:text-5xl">
            Launch campaigns. Fund with confidence.
          </h1>
          <p className="mt-4 text-lg leading-8 text-zinc-600 dark:text-zinc-400">
            Connect your wallet to interact with factory-deployed campaigns on
            Anvil or Sepolia. Governance milestones keep creator payouts
            contributor-approved.
          </p>
        </div>
      </section>
    </div>
  );
}
