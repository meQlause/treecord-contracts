// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {TreecordKeeper} from "../src/TreecordKeeper.sol";
import {TreecordRoles} from "../src/TreecordRoles.sol";

/// @title DeployKeeper
/// @notice Deploys TreecordKeeper against an existing deployment, then configures it once the CRE workflow exists
///         (FR-243, ADR-022). Reads deployments/<chainId>.json and writes deployments/<chainId>-keeper.json, so the
///         frozen deployment file is never touched.
/// @dev `run()` broadcasts with DEPLOYER_PRIVATE_KEY (any funded key works: the keeper needs no role).
///      `configure()` broadcasts with DEPLOYER_PRIVATE_KEY, which must hold DEFAULT_ADMIN_ROLE, and reads
///      CRE_FORWARDER, CRE_WORKFLOW_ID and CRE_WORKFLOW_OWNER (after `cre workflow deploy`).
contract DeployKeeper is Script {
    function run() external returns (TreecordKeeper keeper) {
        string memory chain = vm.toString(block.chainid);
        address roles =
            vm.parseJsonAddress(vm.readFile(string.concat("deployments/", chain, ".json")), ".treecordRoles");

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        keeper = new TreecordKeeper(TreecordRoles(roles));
        vm.stopBroadcast();

        console2.log("TreecordKeeper ", address(keeper));
        console2.log("Roles          ", roles);

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            string memory json = vm.serializeAddress("keeper", "keeper", address(keeper));
            json = vm.serializeUint("keeper", "deployBlock", block.number);
            string memory path = string.concat("deployments/", chain, "-keeper.json");
            vm.writeJson(json, path);
            console2.log("Wrote", path);
        }
    }

    function configure() external {
        string memory path = string.concat("deployments/", vm.toString(block.chainid), "-keeper.json");
        TreecordKeeper keeper = TreecordKeeper(vm.parseJsonAddress(vm.readFile(path), ".keeper"));
        address forwarder = vm.envAddress("CRE_FORWARDER");
        bytes32 workflowId = vm.envBytes32("CRE_WORKFLOW_ID");
        address workflowOwner = vm.envAddress("CRE_WORKFLOW_OWNER");

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        keeper.configure(forwarder, workflowId, workflowOwner);
        vm.stopBroadcast();

        console2.log("Configured     ", address(keeper));
        console2.log("Forwarder      ", forwarder);
        console2.log("Workflow owner ", workflowOwner);
    }
}
