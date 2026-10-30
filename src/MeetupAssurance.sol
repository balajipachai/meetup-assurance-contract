// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title MeetupAssurance
/// @notice All-or-nothing assurance contract for funding a meetup. People pledge ETH before a
///         deadline. If the total reaches the target, the beneficiary collects once. If it does
///         not, every pledger reclaims their own pledge.
/// @dev Lifecycle: Open (now <= deadline) -> Succeeded (deadline passed, total >= target) -> Collected,
///      or Failed (deadline passed, total < target) -> pledgers refund individually.
///      Pledging is only possible up to and including the deadline; collecting and refunding
///      only strictly after it, so the two windows never overlap.
///      Refunds are pulled by each pledger; no function iterates over pledgers.
///      The campaign terms are immutable and set only in the constructor.
contract MeetupAssurance is ReentrancyGuard {
    address public immutable beneficiary;
    uint256 public immutable target;
    uint256 public immutable deadline;

    enum State {
        Open,
        Succeeded,
        Failed,
        Collected
    }

    /// @notice Total ever pledged. Not reduced by refunds, so it keeps showing what was raised.
    uint256 public totalPledged;
    bool public collected;
    mapping(address => uint256) public pledges;

    event Pledged(address indexed pledger, uint256 amount);
    event Refunded(address indexed pledger, uint256 amount);
    event Collected(address indexed beneficiary, uint256 amount);

    error InvalidTerms();
    error DeadlinePassed();
    error ZeroPledge();
    error DeadlineNotPassed();
    error TargetMet();
    error TargetNotMet();
    error NothingToRefund();
    error AlreadyCollected();
    error TransferFailed();

    constructor(address beneficiary_, uint256 target_, uint256 deadline_) {
        // A campaign deadline in days tolerates the seconds of validator timestamp drift.
        // slither-disable-next-line timestamp
        if (beneficiary_ == address(0) || target_ == 0 || deadline_ <= block.timestamp) {
            revert InvalidTerms();
        }
        beneficiary = beneficiary_;
        target = target_;
        deadline = deadline_;
    }

    /// @notice Pledge ETH to the campaign. The credited amount is exactly `msg.value`.
    function pledge() external payable {
        // Deadline is measured in days; validator timestamp drift of seconds is acceptable.
        // slither-disable-next-line timestamp
        if (block.timestamp > deadline) revert DeadlinePassed();
        if (msg.value == 0) revert ZeroPledge();

        pledges[msg.sender] += msg.value;
        totalPledged += msg.value;

        emit Pledged(msg.sender, msg.value);
    }

    /// @notice Where the campaign stands right now.
    function state() public view returns (State) {
        if (collected) return State.Collected;
        // slither-disable-next-line timestamp
        if (block.timestamp <= deadline) return State.Open;
        return totalPledged >= target ? State.Succeeded : State.Failed;
    }

    /// @notice Pledger reclaims their own pledge. Only possible once the deadline has passed
    ///         with the target unmet.
    /// @dev The pledge is zeroed before the ETH is sent (CEI), with a reentrancy guard on top.
    function refund() external nonReentrant {
        if (totalPledged >= target) revert TargetMet();
        // Deadline is measured in days; validator timestamp drift of seconds is acceptable.
        // slither-disable-next-line timestamp
        if (block.timestamp <= deadline) revert DeadlineNotPassed();

        uint256 amount = pledges[msg.sender];
        if (amount == 0) revert NothingToRefund();

        pledges[msg.sender] = 0;

        emit Refunded(msg.sender, amount);

        // .call forwards all gas, unlike transfer's 2300 stipend that breaks smart-wallet pledgers;
        // state is already cleared above and nonReentrant guards the function.
        // slither-disable-next-line low-level-calls
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Pays the beneficiary the full balance once the deadline has passed with the
    ///         target met. Callable once, by anyone.
    function collect() external nonReentrant {
        if (totalPledged < target) revert TargetNotMet();
        // Deadline is measured in days; validator timestamp drift of seconds is acceptable.
        // slither-disable-next-line timestamp
        if (block.timestamp <= deadline) revert DeadlineNotPassed();
        if (collected) revert AlreadyCollected();

        collected = true;
        uint256 amount = address(this).balance;

        emit Collected(beneficiary, amount);

        // .call so a multisig beneficiary can receive; `collected` is already set and nonReentrant guards.
        // slither-disable-next-line low-level-calls
        (bool ok,) = beneficiary.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
