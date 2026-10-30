// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {Campaign} from "./Campaign.sol";
import {TreeRegistry} from "./TreeRegistry.sol";
import {RoleGated, TreecordRoles} from "./TreecordRoles.sol";
import {ICampaign} from "./interfaces/ICampaign.sol";
import {ICampaignFactory} from "./interfaces/ICampaignFactory.sol";
import {IReceiver} from "./interfaces/IReceiver.sol";
import {TreecordConstants as C} from "./libraries/TreecordConstants.sol";
import {Tree, TreeStatus} from "./libraries/TreecordTypes.sol";

/// @title TreecordKeeper
/// @notice Lets a Chainlink CRE workflow settle the two actions anyone may already send: forfeiting a milestone
///         whose window closed unpaid and expiring a dead tree past its replant deadline (FR-243, ADR-022).
/// @dev Holds no role, no funds and no key (NFR-245). Each task is tried on its own, so a task someone else
///      already settled costs nothing and never blocks the rest, and `Enforced` is emitted only for a task this
///      contract actually settled: the "Enforced by Chainlink" badge (FR-244) never claims someone else's call.
contract TreecordKeeper is IReceiver, RoleGated {
    /// @notice One settlement. `kind` 0 forfeits `milestone` of `treeId` in `campaign`; `kind` 1 expires `treeId`
    ///         (`campaign` and `milestone` are ignored and the tree's own campaign is reported).
    struct Task {
        uint8 kind;
        address campaign;
        uint256 treeId;
        uint8 milestone;
    }

    uint8 public constant FORFEIT = 0;
    uint8 public constant EXPIRE = 1;

    /// @notice Tasks per report: one transaction stays far below CRE's 10M gas write limit (FR-243 bounds).
    uint256 public constant MAX_TASKS = 10;

    /// @notice Gas each task must have before it is tried: over 2.5x the dearest task measured (an expire that
    ///         forfeits five milestones, about 77k). With less, the report reverts instead of a task running out of
    ///         gas inside `try` and being skipped as if it were settled (a low gas estimate did that on anvil).
    uint256 public constant MIN_TASK_GAS = 200_000;

    /// @dev Packed metadata: workflow id (32 bytes), workflow name (10 bytes), workflow owner (20 bytes).
    uint256 private constant METADATA_LENGTH = 62;

    /// @notice The Chainlink Forwarder allowed to call `onReport`. Zero until configured, so nothing is accepted.
    address public forwarder;
    /// @notice The CRE workflow allowed to report, and its owner.
    bytes32 public workflowId;
    address public workflowOwner;

    /// @notice A task this contract settled.
    event Enforced(uint8 indexed kind, address indexed campaign, uint256 indexed treeId, uint8 milestone);
    event Configured(address forwarder, bytes32 workflowId, address workflowOwner);

    error UnauthorizedForwarder(address sender);
    error UnauthorizedWorkflow(bytes32 workflowId, address workflowOwner);
    error TooManyTasks(uint256 count);
    error InsufficientGas();

    constructor(TreecordRoles roles_) RoleGated(roles_) {}

    /// @notice Sets the Forwarder and workflow, which are known only after `cre workflow deploy`.
    function configure(address forwarder_, bytes32 workflowId_, address workflowOwner_)
        external
        onlyRoleHolder(DEFAULT_ADMIN_ROLE)
    {
        forwarder = forwarder_;
        workflowId = workflowId_;
        workflowOwner = workflowOwner_;
        emit Configured(forwarder_, workflowId_, workflowOwner_);
    }

    /// @inheritdoc IReceiver
    function onReport(bytes calldata metadata, bytes calldata report) external {
        if (msg.sender != forwarder) revert UnauthorizedForwarder(msg.sender);
        if (metadata.length < METADATA_LENGTH) revert UnauthorizedWorkflow(bytes32(0), address(0));

        bytes32 id = bytes32(metadata[0:32]);
        address owner = address(bytes20(metadata[42:62]));
        if (id != workflowId || owner != workflowOwner) revert UnauthorizedWorkflow(id, owner);

        Task[] memory tasks = abi.decode(report, (Task[]));
        if (tasks.length > MAX_TASKS) revert TooManyTasks(tasks.length);

        for (uint256 i = 0; i < tasks.length; ++i) {
            if (gasleft() < MIN_TASK_GAS) revert InsufficientGas();
            _settle(tasks[i]);
        }
    }

    /// @notice Due tasks among trees `fromTreeId` to `fromTreeId + maxScan - 1`, at most `MAX_TASKS`: every
    ///         unsettled milestone of an Alive or Dead tree whose window closed, and an expiry for every Dead
    ///         tree past its replant deadline. Same rules as the worker's scheduler (`due-tasks.rules.ts`).
    /// @dev shortcut: scans every tree in one eth_call, fine for the demo's tens of trees; past a few thousand
    ///      the workflow should page with `fromTreeId` across runs.
    function findDue(uint256 fromTreeId, uint256 maxScan) external view returns (Task[] memory due) {
        TreeRegistry registry = TreeRegistry(roles.treeRegistry());
        uint256 last = registry.treeCount();
        if (fromTreeId == 0) fromTreeId = 1;
        if (maxScan < last && fromTreeId + maxScan - 1 < last) last = fromTreeId + maxScan - 1;

        due = new Task[](MAX_TASKS);
        uint256 count;
        for (uint256 treeId = fromTreeId; treeId <= last && count < MAX_TASKS; ++treeId) {
            count = _collect(registry.getTree(treeId), treeId, due, count);
        }
        assembly {
            mstore(due, count)
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function _settle(Task memory task) internal {
        if (task.kind == FORFEIT) {
            if (!ICampaignFactory(roles.factory()).isCampaign(task.campaign)) return;
            try ICampaign(task.campaign).forfeitMilestone(task.treeId, task.milestone) {
                emit Enforced(FORFEIT, task.campaign, task.treeId, task.milestone);
            } catch {}
        } else if (task.kind == EXPIRE) {
            TreeRegistry registry = TreeRegistry(roles.treeRegistry());
            try registry.expireDead(task.treeId) {
                emit Enforced(EXPIRE, registry.getTree(task.treeId).campaign, task.treeId, 0);
            } catch {}
        }
    }

    function _collect(Tree memory tree, uint256 treeId, Task[] memory due, uint256 count)
        internal
        view
        returns (uint256)
    {
        if (tree.status != TreeStatus.Alive && tree.status != TreeStatus.Dead) return count;

        Campaign campaign = Campaign(tree.campaign);
        uint8 settled = campaign.paidMask(treeId) | campaign.forfeitedMask(treeId);
        for (uint8 milestone = 0; milestone < C.MILESTONE_COUNT && count < MAX_TASKS; ++milestone) {
            if (settled & (1 << milestone) != 0) continue;
            (, uint256 closesAt) = campaign.milestoneWindow(treeId, milestone);
            if (block.timestamp <= closesAt) break; // later windows close later still
            due[count++] = Task(FORFEIT, tree.campaign, treeId, milestone);
        }

        if (tree.status == TreeStatus.Dead && block.timestamp > tree.replantDeadline && count < MAX_TASKS) {
            due[count++] = Task(EXPIRE, tree.campaign, treeId, 0);
        }
        return count;
    }
}
