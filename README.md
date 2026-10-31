# treecord-contracts

Treecord's Solidity contracts (Foundry): `Campaign`, `CampaignFactory`, `TreeRegistry`, `VerificationGateway`,
`CarbonLedger`, `TreecordRoles`.

Split with its history from `packages/contracts` of [azkawm/treecord-backend](https://github.com/azkawm/treecord-backend)
at `03edfe6`. The contracts are **frozen** (treecord `docs/architecture-decisions.md` ADR-002): reused unchanged.

| Command | What it does |
|---|---|
| `npm install` | OpenZeppelin and forge-std, which `remappings.txt` reads from `node_modules/` |
| `forge test` | Unit, fuzz (512 runs) and invariant (128 × 100) suites on forge's in-memory EVM |
| `npm run anvil` | A local chain: id 31337, port 8545, a block every second |
| `npm run deploy:local` | Deploys everything with `script/Deploy.s.sol` to anvil, writes `deployments/31337.json` |
| `npm run demo-campaign:local` | A demo campaign on that chain |
| `npm run export-abis` | ABIs and addresses as TypeScript, into `generated/` |

`.env.anvil` holds anvil's well-known public dev keys only. Base Sepolia commands read `.env` (see `.env.example`
in the original repository); it is never committed.

## Chainlink keeper (CRE)

`TreecordKeeper` lets a Chainlink CRE workflow settle the two actions anyone may already send: forfeiting a
milestone whose window closed unpaid and expiring a dead tree past its replant deadline (FR-243, ADR-022). It holds
no role and no funds; it accepts a report only from the configured Forwarder with the configured workflow id and
owner, settles at most 10 tasks per report, needs 200k gas per task, and emits `Enforced` only for what it settled.

| Piece | Where |
|---|---|
| Contract and tests | `src/TreecordKeeper.sol`, `test/TreecordKeeper.t.sol` (`forge test --match-contract TreecordKeeperTest`) |
| Workflow | `cre/treecord-keeper/` (TypeScript, `@chainlink/cre-sdk` 1.23.0; `bun test`, `bun x tsc --noEmit`) |
| Deploy and configure | `script/DeployKeeper.s.sol` → `deployments/<chainId>-keeper.json` |
| Demo tree | `script/DemoKeeperTree.s.sol` (180 s time unit, milestone 1 closes 12 min after planting) |
| Demo deployment | `deployments/84532.json` (block 52412421) and `84532-keeper.json`; `main`'s first set is `84532-v1*.json` |

> `typescript` stays on 5.9.3 in the workflow: the SDK's compiler calls the TypeScript 5 API, which TypeScript 7
> does not ship ("ts.ScriptTarget is undefined").

### Run it on Base Sepolia

Keys live in `../backend/.env.sepolia` (gitignored): `DEPLOYER_`, `OPERATOR_`, `ATTESTER_PRIVATE_KEY`.

```bash
# 1. deploy the keeper against deployments/84532.json
node script/with-env.mjs --env ../backend/.env.sepolia \
  forge script script/DeployKeeper.s.sol --rpc-url https://sepolia.base.org --broadcast --slow

# 2. point it at a forwarder and a workflow identity (the deployer holds DEFAULT_ADMIN_ROLE)
CRE_FORWARDER=0x82300bd7c3958625581cc2f77bc6464dcecdf3e5 \
CRE_WORKFLOW_ID=0x1111111111111111111111111111111111111111111111111111111111111111 \
CRE_WORKFLOW_OWNER=0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa \
node script/with-env.mjs --env ../backend/.env.sepolia \
  forge script script/DeployKeeper.s.sol --sig "configure()" --rpc-url https://sepolia.base.org --broadcast --slow

# 3. plant a demo tree; its month-3 window closes 12 minutes later
node script/with-env.mjs --env ../backend/.env.sepolia \
  forge script script/DemoKeeperTree.s.sol --rpc-url https://sepolia.base.org --broadcast --slow

# 4. after the window closes: run the workflow, broadcasting its report (cre/.env holds CRE_ETH_PRIVATE_KEY)
cd cre && cre workflow simulate treecord-keeper --target staging-settings --non-interactive --trigger-index 0 --broadcast
```

| Mode | Forwarder | Workflow id / owner | `readBlock` |
|---|---|---|---|
| `cre workflow simulate --broadcast` | `MockKeystoneForwarder` `0x82300bd7c3958625581cc2f77bc6464dcecdf3e5` | the simulator's placeholders `0x11…11` / `0xaa…aa` | `latest` (one node; its finalized view trails the chain) |
| `cre workflow deploy` (needs deploy access) | `KeystoneForwarder` `0xF8344CFd5c43616a4366C34E3EEE75af79a74482` | the deployed workflow's id and owner | `finalized` (every node reads the same block) |

> The keeper only gets a task the scheduler has not settled first. A worker running `main` against the same
> contracts forfeits within seconds, so the demo runs on its own deployment with the local worker indexer-only
> (`WORKER_MODE=indexer`). The first Chainlink forfeit: tx `0x95878769330de4799f8cb8dbb2fefc8d4440c7e013694f6509f4cdbed942df00`.
