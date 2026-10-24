// Verifies a deployment's contracts on the block explorer, reading addresses from deployments/<chainId>.json.
// Constructor arguments are rebuilt from that file (and CarbonLedger's URI from the chain), so nothing depends
// on broadcast logs. Safe to run again: contracts that are already verified are skipped by the explorer.
//
// Usage: node script/verify.mjs [--chain <id>] [--dry-run]
// Default chain: 84532 (Base Sepolia).
//
// Explorer: Basescan through the Etherscan V2 API when ETHERSCAN_API_KEY is set (one free key from
// etherscan.io covers every chain), otherwise Blockscout, which needs no key.
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const CIRCLE_USDC = {
  84532: "0x036cbd53842c5426634e7929541ec2318f3dcf7e",
};
const EXPLORERS = {
  84532: {
    rpc: "https://sepolia.base.org",
    basescan: "https://sepolia.basescan.org",
    blockscout: "https://base-sepolia.blockscout.com",
  },
};

const args = process.argv.slice(2);
const chainId = Number(args.includes("--chain") ? args[args.indexOf("--chain") + 1] : 84532);
const dryRun = args.includes("--dry-run");

const explorer = EXPLORERS[chainId];
if (!explorer) fail(`No explorer configured for chain ${chainId}.`);
const deploymentPath = resolve(import.meta.dirname, "..", "deployments", `${chainId}.json`);
if (!existsSync(deploymentPath)) fail(`Missing ${deploymentPath}. Deploy first.`);
const d = JSON.parse(readFileSync(deploymentPath, "utf8"));
const rpc = process.env.BASE_SEPOLIA_RPC_URL || explorer.rpc;
const apiKey = process.env.ETHERSCAN_API_KEY;

const carbonUri = run("cast", ["call", d.carbonLedger, "uri(uint256)(string)", "0", "--rpc-url", rpc]).replace(
  /^"|"$/g,
  "",
);

const contracts = [
  ["TreecordRoles", d.treecordRoles, "constructor(address,address)", [d.deployer, d.treasury]],
  ["TreeRegistry", d.treeRegistry, "constructor(address)", [d.treecordRoles]],
  [
    "Campaign",
    d.campaignImplementation,
    "constructor(address,address,address)",
    [d.treecordRoles, d.usdc, d.treeRegistry],
  ],
  ["CampaignFactory", d.campaignFactory, "constructor(address,address)", [d.treecordRoles, d.campaignImplementation]],
  ["VerificationGateway", d.verificationGateway, "constructor(address)", [d.treecordRoles]],
  ["CarbonLedger", d.carbonLedger, "constructor(address,address,string)", [d.treecordRoles, d.usdc, carbonUri]],
];
// Circle's USDC is verified already. Anything else at that slot is the MockUSDC from DEPLOY_MOCK_USDC=true.
if (d.usdc.toLowerCase() !== CIRCLE_USDC[chainId]) contracts.unshift(["MockUSDC", d.usdc, null, []]);

const verifierArgs = apiKey
  ? ["--verifier", "etherscan", "--etherscan-api-key", apiKey]
  : ["--verifier", "blockscout", "--verifier-url", `${explorer.blockscout}/api/`];
const site = apiKey ? explorer.basescan : explorer.blockscout;
console.log(`Verifying ${contracts.length} contracts on ${site}${apiKey ? "" : " (no ETHERSCAN_API_KEY, so Blockscout)"}`);

const failed = [];
for (const [name, address, signature, values] of contracts) {
  const source = name === "MockUSDC" ? `src/mocks/MockUSDC.sol:MockUSDC` : `src/${name}.sol:${name}`;
  const encoded = signature ? run("cast", ["abi-encode", signature, ...values]) : "";
  const forgeArgs = [
    "verify-contract",
    address,
    source,
    "--chain",
    String(chainId),
    ...(encoded ? ["--constructor-args", encoded] : []),
    ...verifierArgs,
    "--watch",
    "--retries",
    "10",
    "--delay",
    "10",
  ];
  console.log(`\n${name} ${address}`);
  if (dryRun) {
    console.log(`  forge ${forgeArgs.map((a) => (a === apiKey ? "<ETHERSCAN_API_KEY>" : a)).join(" ")}`);
    continue;
  }
  const result = spawnSync("forge", forgeArgs, { stdio: "inherit", cwd: resolve(import.meta.dirname, "..") });
  if (result.status === 0) console.log(`  ${site}/address/${address}#code`);
  else failed.push(name);
}

if (failed.length > 0) {
  fail(`\nNot verified: ${failed.join(", ")}. The explorer may still be indexing. Run this again in a minute.`);
}
console.log(dryRun ? "\nDry run: nothing submitted." : "\nAll contracts verified.");

function run(command, commandArgs) {
  const result = spawnSync(command, commandArgs, { encoding: "utf8" });
  if (result.status !== 0) fail(`${command} ${commandArgs[0]} failed:\n${result.stderr || result.error}`);
  return result.stdout.trim();
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
