import { describe, expect, it } from 'bun:test';
import { decodeAbiParameters, type Hex } from 'viem';
import { TASKS, encodeTasks, type Task } from './report';

const CAMPAIGN = '0x0000000000000000000000000000000000000003';
const DUE: Task[] = [
  { kind: 0, campaign: CAMPAIGN, treeId: 3001n, milestone: 1 },
  { kind: 1, campaign: CAMPAIGN, treeId: 3021n, milestone: 0 },
];
// `cast abi-encode "f((uint8,address,uint256,uint8)[])" "[(0,0x…03,3001,1),(1,0x…03,3021,0)]"`: what
// TreecordKeeper.onReport's abi.decode(report, (Task[])) reads
const SOLIDITY = (
  '0x0000000000000000000000000000000000000000000000000000000000000020' +
  '0000000000000000000000000000000000000000000000000000000000000002' +
  '0000000000000000000000000000000000000000000000000000000000000000' +
  '0000000000000000000000000000000000000000000000000000000000000003' +
  '0000000000000000000000000000000000000000000000000000000000000bb9' +
  '0000000000000000000000000000000000000000000000000000000000000001' +
  '0000000000000000000000000000000000000000000000000000000000000001' +
  '0000000000000000000000000000000000000000000000000000000000000003' +
  '0000000000000000000000000000000000000000000000000000000000000bcd' +
  '0000000000000000000000000000000000000000000000000000000000000000') as Hex;

describe('encodeTasks (FR-243: the report TreecordKeeper decodes)', () => {
  it('encodes the tasks exactly as Solidity abi.encode(Task[]) does', () => {
    expect(encodeTasks(DUE)).toBe(SOLIDITY);
  });

  it('round-trips through the Task[] layout', () => {
    const encoded = encodeTasks(DUE);

    expect(encoded).not.toBeNull();
    expect(decodeAbiParameters(TASKS, encoded!)[0]).toEqual(DUE);
  });

  it('returns null when nothing is due, so no report is sent', () => {
    expect(encodeTasks([])).toBeNull();
  });
});
