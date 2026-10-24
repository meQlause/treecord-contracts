// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice 6-decimal test stablecoin with open minting and burning. Used by tests, by the anvil deployment, and on
///         Base Sepolia when the deploy runs with DEPLOY_MOCK_USDC=true instead of using Circle's test USDC.
/// @dev Anyone can mint any amount, so it has no value. Never deploy it to a mainnet.
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USD Coin", "USDC") {}

    /// @notice USDC uses 6 decimals.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mints test tokens to anyone.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burns test tokens from the caller's own balance.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
