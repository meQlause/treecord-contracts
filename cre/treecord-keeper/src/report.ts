// The keeper's report: an ABI-encoded TreecordKeeper.Task[] (contracts/src/TreecordKeeper.sol, FR-243).
import { encodeAbiParameters, parseAbiParameters, type Address, type Hex } from 'viem';

/** `kind` 0 forfeits `milestone` of `treeId`; 1 expires `treeId`. */
export type Task = { kind: number; campaign: Address; treeId: bigint; milestone: number };

export const TASKS = parseAbiParameters(
  '(uint8 kind, address campaign, uint256 treeId, uint8 milestone)[]',
);

/** The report payload, or null when nothing is due: no report, no transaction. */
export const encodeTasks = (tasks: readonly Task[]): Hex | null =>
  tasks.length === 0 ? null : encodeAbiParameters(TASKS, [tasks]);
