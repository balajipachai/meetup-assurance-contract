# Rubric map

Every check the repo is graded on, where it is satisfied, and the test that proves it.
Run `forge test`; every row below must pass. Contract: `src/MeetupAssurance.sol`.

| # | Pts | Check | Where | Test |
|---|----:|-------|-------|------|
| 1 | 15 | Refunds are claimed by each pledger, not pushed in a loop | `refund()` sends `pledges[msg.sender]` to `msg.sender`; no function iterates over pledgers; no owner or beneficiary gate | `test_refund_returnsOwnPledgeToCaller`, `test_refund_isNotRestrictedToBeneficiaryOrOwner` |
| 2 | 15 | Refund clears the pledger's balance before sending ETH | `refund()`: `pledges[msg.sender] = 0` before `.call`, plus OpenZeppelin `nonReentrant` | `test_refund_secondCallReverts`, `test_refund_reentrancyIsBlockedAndPledgeClearedFirst` |
| 3 | 10 | Beneficiary payout can execute only once | `collect()`: `collected` is checked on entry and set before the transfer, plus `nonReentrant` | `test_collect_canOnlyExecuteOnce`, `test_collect_reentrancyIsBlocked` |
| 4 | 8 | Refunds revert once the target has been met | `refund()`: `totalPledged >= target` reverts `TargetMet`, checked first | `test_refund_revertsWhenTargetMet`, `test_refund_revertsWhenTargetExceeded`, `test_refund_revertsAfterDeadlineIfTargetMet` |
| 5 | 7 | Campaign terms cannot be changed after launch | `beneficiary`, `target`, `deadline` are `immutable`, set only in the constructor; there is no owner and no setter | `test_constructor_setsTerms` |
| 6 | 6 | Beneficiary collection checks the target in the contract | `collect()`: `totalPledged < target` reverts `TargetNotMet` | `test_collect_revertsBelowTarget`, `test_collect_revertsWithNoPledges` |
| 7 | 6 | Pledges after the deadline revert | `pledge()`: `block.timestamp > deadline` reverts `DeadlinePassed` | `test_pledge_revertsAfterDeadline`, `test_pledge_allowedAtDeadline` |
| 8 | 5 | Pledge amounts are recorded from `msg.value` | `pledge()` is the only payable function and credits `msg.value`; there is no `receive` or `fallback` | `test_pledge_recordsMsgValue`, `test_noPayableFallback` |
| 9 | 4 | Deployed Sepolia address is recorded in the repo | README "Deployed address", `frontend/config.js`, `broadcast/Deploy.s.sol/11155111/run-latest.json` | `cast code` at the address is non-empty; source verified on Sourcify |
| 10 | 4 | No credentials in tracked files | keystore signing only; `.env` is git-ignored; `.env.example` has no values | `git grep -nE '0x[0-9a-fA-F]{64}'` finds only the deploy record's transaction hashes |

## Brief-level traps

| Trap | Defence | Test |
|------|---------|------|
| The escape hatch (owner-only cancel, emergency withdraw, sweep) | There is no owner and no function that moves funds except `refund` and `collect` | the contract's ABI; `test_noPayableFallback` |
| The invisible refund (refunds work but the page never says so) | A failed campaign shows a red banner, the visitor's own pledge and a "Claim my refund" button | exercised in a browser; see README |
| A developer UI stapled on | Amounts in ETH, a plain sentence for every state, contract errors translated | exercised in a browser; see README |
| The exact deadline boundary | Pledging works at `deadline`, payouts only strictly after; the windows never overlap | `test_pledgeWindowAndPayoutWindowNeverOverlap`, `test_collect_revertsExactlyAtDeadline`, `test_refund_revertsExactlyAtDeadline` |
