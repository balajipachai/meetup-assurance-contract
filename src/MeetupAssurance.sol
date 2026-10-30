// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title MeetupAssurance
/// @notice All-or-nothing assurance contract for funding a meetup. People pledge ETH before a
///         deadline. If the total reaches the target, the beneficiary collects once. If it does
///         not, every pledger reclaims their own pledge.
/// @dev Lifecycle: Open (before deadline) -> Funded (total >= target) -> Collected, or
///      Failed (deadline passed, total < target) -> pledgers refund individually.
///      Refunds are pulled by each pledger; no function iterates over pledgers.
///      The campaign terms are immutable and set only in the constructor.
contract MeetupAssurance {
    address public immutable beneficiary;
    uint256 public immutable target;
    uint256 public immutable deadline;

    uint256 public totalPledged;
    bool public collected;
    mapping(address => uint256) public pledges;

    bool private _locked;

    event Pledged(address indexed pledger, uint256 amount);
    event Refunded(address indexed pledger, uint256 amount);
    event Collected(address indexed beneficiary, uint256 amount);

    error InvalidTerms();
    error DeadlinePassed();
    error ZeroPledge();
    error TargetMet();
    error TargetNotMet();
    error NothingToRefund();
    error AlreadyCollected();
    error TransferFailed();
    error Reentrancy();

    modifier nonReentrant() {
        if (_locked) revert Reentrancy();
        _locked = true;
        _;
        _locked = false;
    }

    constructor(address beneficiary_, uint256 target_, uint256 deadline_) {
        if (beneficiary_ == address(0) || target_ == 0 || deadline_ <= block.timestamp) {
            revert InvalidTerms();
        }
        beneficiary = beneficiary_;
        target = target_;
        deadline = deadline_;
    }

    /// @notice Pledge ETH to the campaign. The credited amount is exactly `msg.value`.
    function pledge() external payable {
        if (block.timestamp > deadline) revert DeadlinePassed();
        if (collected) revert AlreadyCollected();
        if (msg.value == 0) revert ZeroPledge();

        pledges[msg.sender] += msg.value;
        totalPledged += msg.value;

        emit Pledged(msg.sender, msg.value);
    }

    /// @notice Pledger reclaims their own pledge. Only possible while the target is unmet.
    /// @dev The pledge is zeroed before the ETH is sent (CEI), with a reentrancy guard on top.
    function refund() external nonReentrant {
        if (totalPledged >= target) revert TargetMet();

        uint256 amount = pledges[msg.sender];
        if (amount == 0) revert NothingToRefund();

        pledges[msg.sender] = 0;
        totalPledged -= amount;

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Refunded(msg.sender, amount);
    }

    /// @notice Beneficiary collects the full balance once the target is met. Callable once.
    function collect() external nonReentrant {
        if (totalPledged < target) revert TargetNotMet();
        if (collected) revert AlreadyCollected();

        collected = true;
        uint256 amount = address(this).balance;

        (bool ok,) = beneficiary.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Collected(beneficiary, amount);
    }
}
