// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {Campaign} from "../src/Campaign.sol";
import {CampaignFactory} from "../src/CampaignFactory.sol";
import {VerificationGateway} from "../src/VerificationGateway.sol";
import {TreecordConstants as C} from "../src/libraries/TreecordConstants.sol";
import {Attestation, AttestationKind, CampaignConfig} from "../src/libraries/TreecordTypes.sol";

interface IMintable {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title DemoKeeperTree
/// @notice Plants one tree on a fresh short-unit campaign so its milestone-1 window closes unpaid within minutes and
///         the Chainlink keeper can forfeit it live (cre-keeper AC11). Testnets only: it mints the test USDC.
/// @dev Broadcasts with OPERATOR_PRIVATE_KEY (creates, funds, claims, submits) and signs the PLANTED attestation
///      with ATTESTER_PRIVATE_KEY, as the API does on operator approval. The operator is the planter.
///      Env: DEMO_TIME_UNIT_SECONDS (default 180). Milestone 1 closes 4 units after planting.
contract DemoKeeperTree is Script {
    uint32 internal constant TREES = 4;
    uint256 internal constant FUNDING = 20e6;

    function run() external returns (uint256 treeId) {
        uint256 operatorKey = vm.envUint("OPERATOR_PRIVATE_KEY");
        uint256 attesterKey = vm.envUint("ATTESTER_PRIVATE_KEY");
        address operator = vm.addr(operatorKey);
        uint64 unit = uint64(vm.envOr("DEMO_TIME_UNIT_SECONDS", uint256(180)));

        string memory json = vm.readFile(string.concat("deployments/", vm.toString(block.chainid), ".json"));
        CampaignFactory factory = CampaignFactory(vm.parseJsonAddress(json, ".campaignFactory"));
        VerificationGateway gateway = VerificationGateway(vm.parseJsonAddress(json, ".verificationGateway"));
        IMintable usdc = IMintable(vm.parseJsonAddress(json, ".usdc"));

        vm.startBroadcast(operatorKey);
        Campaign campaign = Campaign(factory.createCampaign(_config(operator, unit)));
        usdc.mint(operator, FUNDING);
        usdc.approve(address(campaign), FUNDING);
        campaign.contribute(FUNDING);
        uint256 slotId = uint256(campaign.anchorSlots()) + 1; // the first open slot of a fresh campaign
        campaign.claimSlotsFor(operator, 1);
        treeId = _plant(gateway, attesterKey, address(campaign), slotId, operator);
        vm.stopBroadcast();

        (, uint256 closesAt) = campaign.milestoneWindow(treeId, 1);
        console2.log("Campaign          ", address(campaign));
        console2.log("Tree              ", treeId);
        console2.log("Milestone 1 closes", closesAt);
    }

    /// @dev The PLANTED attestation the API signs on operator approval, submitted straight to the gateway.
    function _plant(VerificationGateway gateway, uint256 attesterKey, address campaign, uint256 slotId, address planter)
        internal
        returns (uint256)
    {
        Attestation memory att = Attestation({
            kind: uint8(AttestationKind.Planted),
            campaign: campaign,
            slotId: slotId,
            treeId: 0,
            planter: planter,
            milestone: 0,
            evidenceHash: keccak256(abi.encode("cre-keeper demo tree", campaign)),
            geohash: bytes8("qqguwvt"),
            score: 9000,
            nonce: uint256(keccak256(abi.encode(campaign, block.timestamp))),
            expiry: uint64(block.timestamp + 1 hours)
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterKey, gateway.hashAttestation(att));
        return gateway.submit(att, abi.encodePacked(r, s, v));
    }

    function _config(address operator, uint64 unit) internal view returns (CampaignConfig memory) {
        return CampaignConfig({
            creator: operator,
            metadataURI: "treecord://demo/cre-keeper",
            speciesCode: bytes32("SWIETENIA_MACROPHYLLA"),
            regionGeohash: bytes8("qqguwvt"),
            regionRadiusM: 5000,
            treeTarget: TREES,
            anchorBps: C.DEFAULT_ANCHOR_BPS,
            perPlanterCap: C.DEFAULT_PER_PLANTER_CAP,
            fundingTarget: FUNDING,
            fundingDeadline: uint64(block.timestamp) + 20 * unit,
            claimDeadline: uint64(block.timestamp) + 40 * unit,
            commitmentUnits: C.MIN_COMMITMENT_UNITS,
            timeUnit: unit,
            split: C.defaultSplit()
        });
    }
}
