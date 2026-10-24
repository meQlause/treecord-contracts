// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Deploy} from "./Deploy.s.sol";

/// @title DeployBaseSepolia
/// @notice Deploy, pointed at Base Sepolia by the script itself, so it needs neither --rpc-url nor --private-key.
///         Only DEPLOYER_PRIVATE_KEY is required. See Deploy for the optional env.
/// @dev   forge script script/DeployBaseSepolia.s.sol            dry run against a fork
///        forge script script/DeployBaseSepolia.s.sol --broadcast
///      RPC: BASE_SEPOLIA_RPC_URL when set, otherwise the public https://sepolia.base.org (rate limited, fine for
///      a deploy).
contract DeployBaseSepolia is Deploy {
    string internal constant PUBLIC_RPC = "https://sepolia.base.org";

    function run() external override returns (Deployment memory) {
        string memory rpc = _envString("BASE_SEPOLIA_RPC_URL");
        vm.createSelectFork(bytes(rpc).length > 0 ? rpc : PUBLIC_RPC);
        require(block.chainid == BASE_SEPOLIA_CHAIN_ID, "DeployBaseSepolia: RPC is not Base Sepolia (84532)");
        return _deploy();
    }
}
