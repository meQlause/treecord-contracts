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
