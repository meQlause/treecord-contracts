// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Campaign} from "../src/Campaign.sol";
import {CampaignFactory} from "../src/CampaignFactory.sol";
import {CarbonLedger} from "../src/CarbonLedger.sol";
import {TreeRegistry} from "../src/TreeRegistry.sol";
import {TreecordRoles} from "../src/TreecordRoles.sol";
import {VerificationGateway} from "../src/VerificationGateway.sol";
import {ITreeRegistry} from "../src/interfaces/ITreeRegistry.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

/// @title Deploy
/// @notice Deploys and wires every Treecord contract, grants backend roles, and writes
///         deployments/<chainId>.json (only when broadcasting). Runs on the chain given with --rpc-url.
///         DeployBaseSepolia selects Base Sepolia itself.
/// @dev Env (only DEPLOYER_PRIVATE_KEY is required, empty values count as unset):
///      - DEPLOYER_PRIVATE_KEY: deploys and holds DEFAULT_ADMIN_ROLE
///      - OPERATOR_ADDRESS or OPERATOR_PRIVATE_KEY: gets OPERATOR_ROLE and ISSUER_ROLE. Default: the deployer
///      - ATTESTER_ADDRESS or ATTESTER_PRIVATE_KEY: gets ATTESTER_ROLE. Default: the deployer
///      - TREASURY_ADDRESS. Default: the deployer
///      - USDC_ADDRESS: the payment token. Default: Circle test USDC on Base Sepolia. Ignored when a MockUSDC is
///        deployed instead
///      - DEPLOY_MOCK_USDC (default false): deploy an open mint and burn MockUSDC instead of using USDC_ADDRESS.
///        Always true on anvil (chain 31337)
///      - CARBON_METADATA_URI
contract Deploy is Script {
    uint256 internal constant ANVIL_CHAIN_ID = 31337;
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    address internal constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    struct Deployment {
        address usdc;
        address roles;
        address treeRegistry;
        address campaignImplementation;
        address factory;
        address gateway;
        address carbonLedger;
    }

    /// @dev Grouped in a struct to keep _deploy() within the stack limit.
    struct Actors {
        uint256 deployerKey;
        address deployer;
        address operator;
        address attester;
        address treasury;
        uint256 deployBlock;
    }

    function run() external virtual returns (Deployment memory) {
        return _deploy();
    }

    function _deploy() internal returns (Deployment memory d) {
        Actors memory a = _actors();
        string memory carbonUri =
            vm.envOr("CARBON_METADATA_URI", string("https://treecord.app/api/carbon/batches/{id}.json"));

        vm.startBroadcast(a.deployerKey);

        d.usdc = _usesMockUsdc() ? address(new MockUSDC()) : _usdcAddress();

        TreecordRoles roles = new TreecordRoles(a.deployer, a.treasury);
        TreeRegistry registry = new TreeRegistry(roles);
        Campaign implementation = new Campaign(roles, IERC20(d.usdc), ITreeRegistry(address(registry)));
        CampaignFactory factory = new CampaignFactory(roles, address(implementation));
        VerificationGateway gateway = new VerificationGateway(roles);
        CarbonLedger ledger = new CarbonLedger(roles, IERC20(d.usdc), carbonUri);

        roles.setFactory(address(factory));
        roles.setTreeRegistry(address(registry));
        roles.setGateway(address(gateway));
        roles.setCarbonLedger(address(ledger));
        roles.grantRole(roles.OPERATOR_ROLE(), a.operator);
        roles.grantRole(roles.ISSUER_ROLE(), a.operator);
        roles.grantRole(roles.ATTESTER_ROLE(), a.attester);

        vm.stopBroadcast();

        d.roles = address(roles);
        d.treeRegistry = address(registry);
        d.campaignImplementation = address(implementation);
        d.factory = address(factory);
        d.gateway = address(gateway);
        d.carbonLedger = address(ledger);

        _log(d, a);
        _write(d, a);
    }

    function _actors() internal view returns (Actors memory a) {
        a.deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        a.deployer = vm.addr(a.deployerKey);
        a.operator = _roleHolder("OPERATOR_ADDRESS", "OPERATOR_PRIVATE_KEY", a.deployer);
        a.attester = _roleHolder("ATTESTER_ADDRESS", "ATTESTER_PRIVATE_KEY", a.deployer);
        a.treasury = _roleHolder("TREASURY_ADDRESS", "", a.deployer);
        // A fresh anvil has nothing before the deploy, and 0 keeps the committed deployments/31337.json stable
        // when anvil mines on an interval.
        a.deployBlock = block.chainid == ANVIL_CHAIN_ID ? 0 : block.number;
    }

    /// @dev The address in addressVar, else the address of the key in keyVar, else the fallback.
    function _roleHolder(string memory addressVar, string memory keyVar, address fallback_)
        internal
        view
        returns (address)
    {
        string memory value = _envString(addressVar);
        if (bytes(value).length > 0) return vm.parseAddress(value);
        if (bytes(keyVar).length > 0) {
            value = _envString(keyVar);
            if (bytes(value).length > 0) return vm.addr(vm.parseUint(value));
        }
        return fallback_;
    }

    function _usdcAddress() internal view returns (address) {
        string memory value = _envString("USDC_ADDRESS");
        if (bytes(value).length > 0) return vm.parseAddress(value);
        require(block.chainid == BASE_SEPOLIA_CHAIN_ID, "Deploy: set USDC_ADDRESS or DEPLOY_MOCK_USDC=true");
        return BASE_SEPOLIA_USDC;
    }

    /// @dev A helper instead of a local variable, which would make _deploy() too deep for the stack.
    function _usesMockUsdc() internal view returns (bool) {
        return block.chainid == ANVIL_CHAIN_ID || vm.envOr("DEPLOY_MOCK_USDC", false);
    }

    /// @dev An unset variable and an empty one (NAME= in .env) both read as "".
    function _envString(string memory name) internal view returns (string memory) {
        return vm.envOr(name, string(""));
    }

    function _write(Deployment memory d, Actors memory a) internal {
        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console2.log("Dry run: deployments file not written. Re-run with --broadcast.");
            return;
        }
        string memory key = "deployment";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeUint(key, "deployBlock", a.deployBlock);
        vm.serializeAddress(key, "deployer", a.deployer);
        vm.serializeAddress(key, "operator", a.operator);
        vm.serializeAddress(key, "attester", a.attester);
        vm.serializeAddress(key, "treasury", a.treasury);
        vm.serializeAddress(key, "usdc", d.usdc);
        vm.serializeAddress(key, "treecordRoles", d.roles);
        vm.serializeAddress(key, "treeRegistry", d.treeRegistry);
        vm.serializeAddress(key, "campaignImplementation", d.campaignImplementation);
        vm.serializeAddress(key, "campaignFactory", d.factory);
        vm.serializeAddress(key, "verificationGateway", d.gateway);
        string memory json = vm.serializeAddress(key, "carbonLedger", d.carbonLedger);

        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console2.log("Wrote", path);
    }

    function _log(Deployment memory d, Actors memory a) internal view {
        console2.log("Chain id             ", block.chainid);
        console2.log("Deployer (admin)     ", a.deployer);
        console2.log("Operator + issuer    ", a.operator);
        console2.log("Attester             ", a.attester);
        console2.log("Treasury             ", a.treasury);
        console2.log("Deploy block         ", a.deployBlock);
        console2.log("USDC                 ", d.usdc);
        console2.log("TreecordRoles        ", d.roles);
        console2.log("TreeRegistry         ", d.treeRegistry);
        console2.log("Campaign impl        ", d.campaignImplementation);
        console2.log("CampaignFactory      ", d.factory);
        console2.log("VerificationGateway  ", d.gateway);
        console2.log("CarbonLedger         ", d.carbonLedger);
        if (_usesMockUsdc()) console2.log("USDC is a MockUSDC. Set USDC_ADDRESS to", d.usdc, "for the web app.");
        if (a.operator == a.deployer || a.attester == a.deployer || a.treasury == a.deployer) {
            console2.log("Note: the deployer also holds a backend role or the treasury. Use the deployer key for it.");
        }
    }
}
