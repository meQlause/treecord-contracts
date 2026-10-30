// Chainlink CRE workflow (FR-243, ADR-022): on a cron, ask TreecordKeeper which forfeits and expiries are due and
// send them back to it as one signed report through the Chainlink Forwarder. It reads only the chain.
import {
  bytesToHex,
  CronCapability,
  EVMClient,
  encodeCallMsg,
  getNetwork,
  handler,
  LAST_FINALIZED_BLOCK_NUMBER,
  prepareReportRequest,
  Runner,
  type Runtime,
  TxStatus,
} from '@chainlink/cre-sdk';
import { type Address, decodeFunctionResult, encodeFunctionData, parseAbi, zeroAddress } from 'viem';
import { z } from 'zod';
import { encodeTasks } from './src/report';

const configSchema = z.object({
  schedule: z.string(),
  chainSelectorName: z.string(),
  keeperAddress: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
  // trees findDue scans per run, from tree 1 (TreecordKeeper.findDue)
  maxScan: z.string().regex(/^[1-9][0-9]*$/),
  gasLimit: z.string().regex(/^[1-9][0-9]*$/),
});

type Config = z.infer<typeof configSchema>;

const RECEIVER_REVERTED = 1;

const KEEPER_ABI = parseAbi([
  'function findDue(uint256 fromTreeId, uint256 maxScan) view returns ((uint8 kind, address campaign, uint256 treeId, uint8 milestone)[])',
]);

const onCronTrigger = (runtime: Runtime<Config>): string => {
  const { chainSelectorName, keeperAddress, maxScan, gasLimit } = runtime.config;
  const network = getNetwork({ chainFamily: 'evm', chainSelectorName, isTestnet: true });

  if (!network) {
    throw new Error(`Network not found for chain selector name: ${chainSelectorName}`);
  }

  const evmClient = new EVMClient(network.chainSelector.selector);
  const keeper = keeperAddress as Address;
  // finalized, so every node reads the same block and the DON agrees on one report
  const read = evmClient
    .callContract(runtime, {
      call: encodeCallMsg({
        from: zeroAddress,
        to: keeper,
        data: encodeFunctionData({
          abi: KEEPER_ABI,
          functionName: 'findDue',
          args: [1n, BigInt(maxScan)],
        }),
      }),
      blockNumber: LAST_FINALIZED_BLOCK_NUMBER,
    })
    .result();
  const due = decodeFunctionResult({
    abi: KEEPER_ABI,
    functionName: 'findDue',
    data: bytesToHex(read.data),
  });
  const payload = encodeTasks(due);

  if (payload === null) {
    runtime.log('Nothing due');

    return 'nothing due';
  }

  const report = runtime.report(prepareReportRequest(payload)).result();
  const write = evmClient
    .writeReport(runtime, { receiver: keeper, report, gasConfig: { gasLimit } })
    .result();

  if (write.txStatus !== TxStatus.SUCCESS) {
    throw new Error(`Failed to write report: ${write.errorMessage || write.txStatus}`);
  }

  // the transaction can succeed while onReport reverts; the SDK root does not export the EVM enum (1 = REVERTED)
  if (write.receiverContractExecutionStatus === RECEIVER_REVERTED) {
    throw new Error(`TreecordKeeper.onReport reverted: ${write.errorMessage ?? 'no message'}`);
  }

  const txHash = bytesToHex(write.txHash ?? new Uint8Array(32));

  runtime.log(`Sent ${due.length} task(s) in ${txHash}`);

  return txHash;
};

const initWorkflow = (config: Config) => {
  const cron = new CronCapability();

  return [handler(cron.trigger({ schedule: config.schedule }), onCronTrigger)];
};

export async function main() {
  const runner = await Runner.newRunner<Config>({ configSchema });

  await runner.run(initWorkflow);
}
