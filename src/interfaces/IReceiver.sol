// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IReceiver
/// @notice Chainlink CRE's consumer interface: the Forwarder calls `onReport` once it has verified the DON's
///         signatures. Copied from https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts
///         instead of installing a Chainlink package for twelve lines.
interface IReceiver is IERC165 {
    /// @param metadata Packed workflow id (32 bytes), workflow name (10 bytes) and workflow owner (20 bytes).
    /// @param report The workflow's ABI-encoded payload.
    function onReport(bytes calldata metadata, bytes calldata report) external;
}
