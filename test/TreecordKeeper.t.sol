// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {Campaign} from "../src/Campaign.sol";
import {TreecordKeeper} from "../src/TreecordKeeper.sol";
import {ICampaign} from "../src/interfaces/ICampaign.sol";
import {IReceiver} from "../src/interfaces/IReceiver.sol";
import {TreeStatus, Unauthorized} from "../src/libraries/TreecordTypes.sol";
import {TestBase} from "./utils/TestBase.sol";

/// @notice FR-243, NFR-245: the Chainlink keeper settles due forfeits and expiries reported by the CRE workflow.
contract TreecordKeeperTest is TestBase {
    bytes32 internal constant WORKFLOW_ID = keccak256("treecord-keeper");
    bytes10 internal constant WORKFLOW_NAME = bytes10("keeper");

    TreecordKeeper internal keeper;
    Campaign internal c;
    address internal forwarder = makeAddr("forwarder");
    address internal workflowOwner = makeAddr("workflowOwner");
    uint256 internal treeA;
    uint256 internal treeB;
    uint256 internal treeC;

    function setUp() public override {
        super.setUp();
        keeper = new TreecordKeeper(roles);
        vm.prank(admin);
        keeper.configure(forwarder, WORKFLOW_ID, workflowOwner);

        c = _activeCampaign();
        _claim(c, planter1, 3);
        treeA = _plant(c, 3, planter1);
        treeB = _plant(c, 4, planter1);
        treeC = _plant(c, 5, planter1);
    }

    // T1
    function test_forwarderReportForfeitsClosedWindow() public {
        _warpPastClose(c, treeA, 1);

        vm.expectEmit(address(c));
        emit ICampaign.MilestoneForfeited(treeA, 1, M0);
        vm.expectEmit(address(keeper));
        emit TreecordKeeper.Enforced(0, address(c), treeA, 1);
        _send(_one(_forfeit(address(c), treeA, 1)));

        assertEq(c.forfeitedPool(), M0);
    }

    // T2
    function test_settledTaskIsSkippedAndTheRestStillSettle() public {
        _warpPastClose(c, treeA, 1);
        c.forfeitMilestone(treeA, 1); // the scheduler got there first

        TreecordKeeper.Task[] memory tasks = new TreecordKeeper.Task[](2);
        tasks[0] = _forfeit(address(c), treeA, 1);
        tasks[1] = _forfeit(address(c), treeB, 1);
        vm.recordLogs();
        _send(tasks);

        uint256[] memory enforced = _enforcedTrees(vm.getRecordedLogs());
        assertEq(enforced.length, 1);
        assertEq(enforced[0], treeB);
        assertEq(c.forfeitedPool(), 2 * M0);
    }

    // T22: found in the P2 anvil dry run, where a gas estimate starved the forfeit and the report "succeeded"
    function test_neverSucceedsWithoutSettlingADueTaskAtAnyGasLimit() public {
        _warpPastClose(c, treeA, 1);
        bytes memory call = abi.encodeCall(
            keeper.onReport, (_metadata(WORKFLOW_ID, workflowOwner), abi.encode(_one(_forfeit(address(c), treeA, 1))))
        );
        uint256 before = vm.snapshotState();

        vm.startPrank(forwarder);
        for (uint256 gas = 30_000; gas <= 400_000; gas += 1_000) {
            (bool ok,) = address(keeper).call{gas: gas}(call);
            if (ok) assertEq(c.forfeitedPool(), M0, "a report succeeded without settling the due task");
            vm.revertToState(before);
        }
        vm.stopPrank();
    }

    // T3
    function test_expireRemovesDeadTreePastDeadline() public {
        _reportDead(c, treeA, planter1);
        vm.warp(_now() + 2 * UNIT + 1);

        vm.expectEmit(address(keeper));
        emit TreecordKeeper.Enforced(1, address(c), treeA, 0);
        _send(_one(_expire(treeA)));

        assertEq(uint8(registry.statusOf(treeA)), uint8(TreeStatus.Removed));
    }

    // T4
    function test_revertWhen_senderIsNotTheForwarder() public {
        bytes memory report = abi.encode(_one(_forfeit(address(c), treeA, 1)));
        bytes memory metadata = _metadata(WORKFLOW_ID, workflowOwner);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(TreecordKeeper.UnauthorizedForwarder.selector, outsider));
        keeper.onReport(metadata, report);
    }

    // T5
    function test_revertWhen_workflowIdOrOwnerDiffers() public {
        bytes memory report = abi.encode(_one(_forfeit(address(c), treeA, 1)));
        bytes32 otherId = keccak256("other");

        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(TreecordKeeper.UnauthorizedWorkflow.selector, otherId, workflowOwner));
        keeper.onReport(_metadata(otherId, workflowOwner), report);

        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(TreecordKeeper.UnauthorizedWorkflow.selector, WORKFLOW_ID, outsider));
        keeper.onReport(_metadata(WORKFLOW_ID, outsider), report);

        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(TreecordKeeper.UnauthorizedWorkflow.selector, bytes32(0), address(0)));
        keeper.onReport(abi.encodePacked(WORKFLOW_ID), report);
    }

    // T6
    function test_nonFactoryCampaignIsSkipped() public {
        _warpPastClose(c, treeA, 1);

        TreecordKeeper.Task[] memory tasks = new TreecordKeeper.Task[](2);
        tasks[0] = _forfeit(outsider, treeA, 1);
        tasks[1] = _forfeit(address(c), treeA, 1);
        vm.recordLogs();
        _send(tasks);

        uint256[] memory enforced = _enforcedTrees(vm.getRecordedLogs());
        assertEq(enforced.length, 1);
        assertEq(enforced[0], treeA);
    }

    // T7
    function test_revertWhen_reportHasMoreThanTenTasks() public {
        TreecordKeeper.Task[] memory tasks = new TreecordKeeper.Task[](11);
        for (uint256 i = 0; i < tasks.length; ++i) {
            tasks[i] = _forfeit(address(c), treeA, 1);
        }

        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(TreecordKeeper.TooManyTasks.selector, 11));
        keeper.onReport(_metadata(WORKFLOW_ID, workflowOwner), abi.encode(tasks));
    }

    // T8
    function test_findDueListsOnlyClosedUnsettledWindowsOfUnflaggedTrees() public {
        _warpToOpen(c, treeA, 1);
        _checkIn(c, treeA, planter1, 1); // paid
        vm.prank(donorA);
        registry.flag(treeC, keccak256("check"));
        _warpPastClose(c, treeB, 1); // milestone 2 still upcoming for every tree

        TreecordKeeper.Task[] memory due = keeper.findDue(1, 100);
        assertEq(due.length, 1);
        assertEq(due[0].kind, 0);
        assertEq(due[0].campaign, address(c));
        assertEq(due[0].treeId, treeB);
        assertEq(due[0].milestone, 1);

        c.forfeitMilestone(treeB, 1);
        assertEq(keeper.findDue(1, 100).length, 0);
    }

    // T8
    function test_findDueListsExpiredDeadTree() public {
        _reportDead(c, treeA, planter1);
        vm.warp(_now() + 2 * UNIT + 1);

        TreecordKeeper.Task[] memory due = keeper.findDue(1, 100);
        assertEq(due.length, 1);
        assertEq(due[0].kind, 1);
        assertEq(due[0].campaign, address(c));
        assertEq(due[0].treeId, treeA);
    }

    // T8
    function test_findDueStopsAtTenTasksAndHonoursTheScanWindow() public {
        _warpPastClose(c, treeA, 5); // milestones 1 to 5 closed for all three trees: 15 due

        assertEq(keeper.findDue(1, 100).length, 10);
        assertEq(keeper.findDue(treeC, 1).length, 5);
        assertEq(keeper.findDue(treeC + 1, 100).length, 0);
    }

    // T9
    function test_revertWhen_nonAdminConfigures() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, outsider));
        keeper.configure(outsider, WORKFLOW_ID, outsider);
    }

    // T9
    function test_supportsReceiverInterfaces() public view {
        assertTrue(keeper.supportsInterface(type(IReceiver).interfaceId));
        assertTrue(keeper.supportsInterface(type(IERC165).interfaceId));
        assertFalse(keeper.supportsInterface(0xdeadbeef));
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    /// @dev Chainlink's packed metadata: workflow id (32), workflow name (10), workflow owner (20).
    function _metadata(bytes32 id, address owner) internal pure returns (bytes memory) {
        return abi.encodePacked(id, WORKFLOW_NAME, owner);
    }

    function _send(TreecordKeeper.Task[] memory tasks) internal {
        vm.prank(forwarder);
        keeper.onReport(_metadata(WORKFLOW_ID, workflowOwner), abi.encode(tasks));
    }

    function _forfeit(address campaign, uint256 treeId, uint8 milestone)
        internal
        pure
        returns (TreecordKeeper.Task memory)
    {
        return TreecordKeeper.Task({kind: 0, campaign: campaign, treeId: treeId, milestone: milestone});
    }

    function _expire(uint256 treeId) internal pure returns (TreecordKeeper.Task memory) {
        return TreecordKeeper.Task({kind: 1, campaign: address(0), treeId: treeId, milestone: 0});
    }

    function _one(TreecordKeeper.Task memory task) internal pure returns (TreecordKeeper.Task[] memory tasks) {
        tasks = new TreecordKeeper.Task[](1);
        tasks[0] = task;
    }

    /// @dev Tree ids of the keeper's Enforced logs, in order.
    function _enforcedTrees(Vm.Log[] memory logs) internal view returns (uint256[] memory trees) {
        uint256 count;
        trees = new uint256[](logs.length);
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == address(keeper) && logs[i].topics[0] == TreecordKeeper.Enforced.selector) {
                trees[count++] = uint256(logs[i].topics[3]);
            }
        }
        assembly {
            mstore(trees, count)
        }
    }
}
