# treecord-contracts

Treecord's Solidity contracts (Foundry): `Campaign`, `CampaignFactory`, `TreeRegistry`, `VerificationGateway`,
`CarbonLedger`, `TreecordRoles`, plus `MockUSDC`, a test token for demos.

Split with its history from `packages/contracts` of [azkawm/treecord-backend](https://github.com/azkawm/treecord-backend)
at `03edfe6`. The contracts are **frozen** (treecord `docs/architecture-decisions.md` ADR-002): reused unchanged. Later
updates from the monorepo only touch the deploy scripts and the test token in `src/mocks/`.

## Commands

| Command | What it does |
|---|---|
| `npm install` | OpenZeppelin and forge-std, which `remappings.txt` reads from `node_modules/` |
| `forge test` | Unit, fuzz (512 runs) and invariant (128 × 100) suites on forge's in-memory EVM |
| `npm run anvil` | A local chain: id 31337, port 8545, a block every second |
| `npm run deploy:local` | Deploys everything with `script/Deploy.s.sol` to anvil, writes `deployments/31337.json` |
| `npm run demo-campaign:local` | A demo campaign on that chain |
| `npm run simulate:base-sepolia` | Dry run of the Base Sepolia deploy against a fork. Sends nothing |
| `npm run deploy:base-sepolia` | Deploys to Base Sepolia, writes `deployments/84532.json`, then verifies every contract |
| `npm run verify:base-sepolia` | Verification only. Safe to run again: verified contracts are skipped |
| `npm run export-abis` | ABIs and addresses as TypeScript, into `generated/` |

`.env.anvil` holds anvil's well-known public dev keys only. Base Sepolia commands read `.env`, which is never committed.

## Deploying to Base Sepolia

`script/DeployBaseSepolia.s.sol` selects Base Sepolia itself with `vm.createSelectFork` and broadcasts with
`DEPLOYER_PRIVATE_KEY`, so it needs neither `--rpc-url` nor `--private-key`.

1. `cp .env.example .env` and set `DEPLOYER_PRIVATE_KEY`. Everything else is optional (see the comments in
   `.env.example`): operator, attester and treasury default to the deployer, the RPC to `https://sepolia.base.org`,
   and the token to Circle test USDC. `DEPLOY_MOCK_USDC=true` deploys a MockUSDC instead.
2. Fund the deployer with Base Sepolia ETH. The deploy uses about 15M gas, roughly 0.0002 ETH.
3. `npm run simulate:base-sepolia`, then `npm run deploy:base-sepolia`.

Verification goes to Basescan when `ETHERSCAN_API_KEY` is set (one free Etherscan V2 key covers every chain), and to
Blockscout otherwise. `script/verify.mjs` rebuilds the constructor arguments from `deployments/84532.json`, so it works
without the broadcast logs. `node script/verify.mjs --dry-run` prints the commands without sending them.

The roles:

| Role | Holder | Can |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` | Deployer | Grant and revoke roles, change the treasury. Contract links are set once and cannot be redirected |
| `OPERATOR_ROLE` | Operator | Claim slots for planters (so they never pay gas), assign anchor slots, resolve flags, set carbon estimates and prices |
| `ISSUER_ROLE` | Operator | Mirror registry credit issuance into `CarbonLedger` |
| `ATTESTER_ROLE` | Attester | Sign the EIP-712 attestations that register trees and release payouts. Never sends transactions |

## MockUSDC

`src/mocks/MockUSDC.sol` is a plain OpenZeppelin ERC-20, "Mock USD Coin" (`USDC`, 6 decimals). Anyone can call
`mint(to, amount)`, and `burn(amount)` destroys tokens from the caller's own balance only. It has no value. Never deploy
it to a mainnet.

```sh
cast send <MockUSDC> "mint(address,uint256)" <to> 5000000 --rpc-url https://sepolia.base.org --private-key <key>  # 5 USDC
```

## Deployed on Base Sepolia (84532)

Deploy block 49578967. All contracts are verified on Basescan.

| Contract | Address |
|---|---|
| TreecordRoles | [`0x2c8Dd1AAED26faA310a8F234bc1Bc15478aD6c5D`](https://sepolia.basescan.org/address/0x2c8Dd1AAED26faA310a8F234bc1Bc15478aD6c5D#code) |
| TreeRegistry | [`0x9cd271599C2c3DF6d2489f16eC1c00D74F617B1D`](https://sepolia.basescan.org/address/0x9cd271599C2c3DF6d2489f16eC1c00D74F617B1D#code) |
| Campaign (implementation) | [`0xa860c2ed19F9d142F7486b83A840fa032A1d24e5`](https://sepolia.basescan.org/address/0xa860c2ed19F9d142F7486b83A840fa032A1d24e5#code) |
| CampaignFactory | [`0xB963c74a7a1456dd1f37252fBa53eEeF8E18e505`](https://sepolia.basescan.org/address/0xB963c74a7a1456dd1f37252fBa53eEeF8E18e505#code) |
| VerificationGateway | [`0x934a8B3B781de9c2bEC0cc68D775a17a91C88894`](https://sepolia.basescan.org/address/0x934a8B3B781de9c2bEC0cc68D775a17a91C88894#code) |
| CarbonLedger | [`0x6fFD8F249Ef0e41f0677AC57bc6c4FbFC64407f9`](https://sepolia.basescan.org/address/0x6fFD8F249Ef0e41f0677AC57bc6c4FbFC64407f9#code) |
| MockUSDC | [`0xAd58b764cc617E4511C6FAFCc949d840706e4303`](https://sepolia.basescan.org/address/0xAd58b764cc617E4511C6FAFCc949d840706e4303#code) |

| Wallet | Address |
|---|---|
| Deployer (admin) and treasury | `0x4894E5fc077A2eE362Df6d1c6020f03164BbE528` |
| Operator (operator and issuer) | `0xC1b7306c94bFAC47f3749dF39a59054A4D47D531` |
| Attester | `0x9aebBb9b3dae13c7Ce95961354f0CE540B351B42` |

The same values are in `deployments/84532.json`.
