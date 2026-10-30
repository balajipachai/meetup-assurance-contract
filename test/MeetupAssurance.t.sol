// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MeetupAssurance} from "../src/MeetupAssurance.sol";

contract ReentrantPledger {
    MeetupAssurance public immutable campaign;
    uint256 public attempts;
    bool public reenterSucceeded;

    constructor(MeetupAssurance campaign_) {
        campaign = campaign_;
    }

    function pledge() external payable {
        campaign.pledge{value: msg.value}();
    }

    function attack() external {
        campaign.refund();
    }

    receive() external payable {
        attempts++;
        if (attempts < 3) {
            try campaign.refund() {
                reenterSucceeded = true;
            } catch {}
        }
    }
}

contract ReentrantBeneficiary {
    MeetupAssurance public campaign;
    uint256 public attempts;
    bool public reenterSucceeded;

    function setCampaign(MeetupAssurance campaign_) external {
        campaign = campaign_;
    }

    receive() external payable {
        attempts++;
        if (attempts < 3) {
            try campaign.collect() {
                reenterSucceeded = true;
            } catch {}
        }
    }
}

contract MeetupAssuranceTest is Test {
    MeetupAssurance internal campaign;

    address internal beneficiary = makeAddr("beneficiary");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant TARGET = 10 ether;
    uint256 internal deadline;

    function setUp() public {
        deadline = block.timestamp + 7 days;
        campaign = new MeetupAssurance(beneficiary, TARGET, deadline);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    // ---------- constructor ----------

    function test_constructor_setsTerms() public view {
        assertEq(campaign.beneficiary(), beneficiary);
        assertEq(campaign.target(), TARGET);
        assertEq(campaign.deadline(), deadline);
    }

    function test_constructor_revertsOnZeroBeneficiary() public {
        vm.expectRevert(MeetupAssurance.InvalidTerms.selector);
        new MeetupAssurance(address(0), TARGET, deadline);
    }

    function test_constructor_revertsOnZeroTarget() public {
        vm.expectRevert(MeetupAssurance.InvalidTerms.selector);
        new MeetupAssurance(beneficiary, 0, deadline);
    }

    function test_constructor_revertsOnPastDeadline() public {
        vm.expectRevert(MeetupAssurance.InvalidTerms.selector);
        new MeetupAssurance(beneficiary, TARGET, block.timestamp);
    }

    // ---------- pledge ----------

    function test_pledge_recordsMsgValue() public {
        vm.prank(alice);
        campaign.pledge{value: 3 ether}();

        assertEq(campaign.pledges(alice), 3 ether);
        assertEq(campaign.totalPledged(), 3 ether);
        assertEq(address(campaign).balance, 3 ether);
    }

    function test_pledge_accumulatesPerPledger() public {
        vm.startPrank(alice);
        campaign.pledge{value: 1 ether}();
        campaign.pledge{value: 2 ether}();
        vm.stopPrank();

        assertEq(campaign.pledges(alice), 3 ether);
    }

    function test_pledge_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit MeetupAssurance.Pledged(alice, 1 ether);
        vm.prank(alice);
        campaign.pledge{value: 1 ether}();
    }

    function test_pledge_revertsOnZeroValue() public {
        vm.prank(alice);
        vm.expectRevert(MeetupAssurance.ZeroPledge.selector);
        campaign.pledge{value: 0}();
    }

    function test_pledge_revertsAfterDeadline() public {
        vm.warp(deadline + 1);
        vm.prank(alice);
        vm.expectRevert(MeetupAssurance.DeadlinePassed.selector);
        campaign.pledge{value: 1 ether}();
    }

    function test_pledge_allowedAtDeadline() public {
        vm.warp(deadline);
        vm.prank(alice);
        campaign.pledge{value: 1 ether}();
        assertEq(campaign.pledges(alice), 1 ether);
    }

    function test_pledge_revertsAfterCollected() public {
        vm.prank(alice);
        campaign.pledge{value: TARGET}();
        campaign.collect();

        vm.prank(bob);
        vm.expectRevert(MeetupAssurance.AlreadyCollected.selector);
        campaign.pledge{value: 1 ether}();
    }

    function test_noPayableFallback() public {
        vm.prank(alice);
        (bool ok,) = address(campaign).call{value: 1 ether}("");
        assertFalse(ok);
    }

    // ---------- refund ----------

    function test_refund_returnsOwnPledgeToCaller() public {
        vm.prank(alice);
        campaign.pledge{value: 3 ether}();
        vm.prank(bob);
        campaign.pledge{value: 2 ether}();

        uint256 before = alice.balance;
        vm.prank(alice);
        campaign.refund();

        assertEq(alice.balance, before + 3 ether);
        assertEq(campaign.pledges(alice), 0);
        assertEq(campaign.pledges(bob), 2 ether);
        assertEq(campaign.totalPledged(), 2 ether);
    }

    function test_refund_worksAfterDeadlineWhenTargetMissed() public {
        vm.prank(alice);
        campaign.pledge{value: 3 ether}();
        vm.warp(deadline + 1 days);

        vm.prank(alice);
        campaign.refund();
        assertEq(campaign.pledges(alice), 0);
    }

    function test_refund_isNotRestrictedToBeneficiaryOrOwner() public {
        vm.prank(alice);
        campaign.pledge{value: 1 ether}();

        vm.prank(beneficiary);
        vm.expectRevert(MeetupAssurance.NothingToRefund.selector);
        campaign.refund();
    }

    function test_refund_secondCallReverts() public {
        vm.prank(alice);
        campaign.pledge{value: 1 ether}();

        vm.startPrank(alice);
        campaign.refund();
        vm.expectRevert(MeetupAssurance.NothingToRefund.selector);
        campaign.refund();
        vm.stopPrank();
    }

    function test_refund_revertsWhenTargetMet() public {
        vm.prank(alice);
        campaign.pledge{value: TARGET}();

        vm.prank(alice);
        vm.expectRevert(MeetupAssurance.TargetMet.selector);
        campaign.refund();
    }

    function test_refund_revertsWhenTargetExceeded() public {
        vm.prank(alice);
        campaign.pledge{value: TARGET}();
        vm.prank(bob);
        campaign.pledge{value: 5 ether}();

        vm.prank(bob);
        vm.expectRevert(MeetupAssurance.TargetMet.selector);
        campaign.refund();
    }

    function test_refund_revertsAfterDeadlineIfTargetMet() public {
        vm.prank(alice);
        campaign.pledge{value: TARGET}();
        vm.warp(deadline + 1);

        vm.prank(alice);
        vm.expectRevert(MeetupAssurance.TargetMet.selector);
        campaign.refund();
    }

    function test_refund_reentrancyIsBlockedAndPledgeClearedFirst() public {
        ReentrantPledger attacker = new ReentrantPledger(campaign);
        vm.deal(address(attacker), 5 ether);
        attacker.pledge{value: 2 ether}();
        vm.prank(bob);
        campaign.pledge{value: 3 ether}();

        attacker.attack();

        assertGt(attacker.attempts(), 0, "attacker never re-entered");
        assertFalse(attacker.reenterSucceeded());
        // 5 ether pre-funded + 2 ether refunded once; the pledge itself was paid by this test contract
        assertEq(address(attacker).balance, 7 ether);
        assertEq(address(campaign).balance, 3 ether);
        assertEq(campaign.pledges(bob), 3 ether);
    }

    // ---------- collect ----------

    function test_collect_paysBeneficiaryWhenTargetMet() public {
        vm.prank(alice);
        campaign.pledge{value: 6 ether}();
        vm.prank(bob);
        campaign.pledge{value: 5 ether}();

        campaign.collect();

        assertEq(beneficiary.balance, 11 ether);
        assertEq(address(campaign).balance, 0);
        assertTrue(campaign.collected());
    }

    function test_collect_revertsBelowTarget() public {
        vm.prank(alice);
        campaign.pledge{value: TARGET - 1}();

        vm.expectRevert(MeetupAssurance.TargetNotMet.selector);
        campaign.collect();
    }

    function test_collect_revertsWithNoPledges() public {
        vm.expectRevert(MeetupAssurance.TargetNotMet.selector);
        campaign.collect();
    }

    function test_collect_canOnlyExecuteOnce() public {
        vm.prank(alice);
        campaign.pledge{value: TARGET}();

        campaign.collect();
        vm.expectRevert(MeetupAssurance.AlreadyCollected.selector);
        campaign.collect();
        assertEq(beneficiary.balance, TARGET);
    }

    function test_collect_reentrancyIsBlocked() public {
        ReentrantBeneficiary evil = new ReentrantBeneficiary();
        MeetupAssurance c = new MeetupAssurance(address(evil), TARGET, deadline);
        evil.setCampaign(c);

        vm.prank(alice);
        c.pledge{value: TARGET}();
        vm.prank(bob);
        c.pledge{value: 1 ether}();

        c.collect();

        assertGt(evil.attempts(), 0, "beneficiary never re-entered");
        assertFalse(evil.reenterSucceeded());
        assertEq(address(evil).balance, TARGET + 1 ether);
    }

    function test_collect_worksAfterDeadline() public {
        vm.prank(alice);
        campaign.pledge{value: TARGET}();
        vm.warp(deadline + 30 days);

        campaign.collect();
        assertEq(beneficiary.balance, TARGET);
    }

    // ---------- invariants ----------

    function testFuzz_refundAndCollectAreMutuallyExclusive(uint96 a, uint96 b) public {
        a = uint96(bound(a, 1, 50 ether));
        b = uint96(bound(b, 1, 50 ether));

        vm.prank(alice);
        campaign.pledge{value: a}();
        vm.prank(bob);
        campaign.pledge{value: b}();

        if (uint256(a) + uint256(b) >= TARGET) {
            campaign.collect();
            vm.prank(alice);
            vm.expectRevert(MeetupAssurance.TargetMet.selector);
            campaign.refund();
        } else {
            vm.expectRevert(MeetupAssurance.TargetNotMet.selector);
            campaign.collect();
            vm.prank(alice);
            campaign.refund();
            vm.prank(bob);
            campaign.refund();
            assertEq(address(campaign).balance, 0);
        }
    }
}
