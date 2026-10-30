# Meetup Assurance Contract

An all-or-nothing assurance contract for funding a meetup: **the meetup only happens if we all chip in.**
People pledge ETH before a deadline. If the pledged total reaches the target, the beneficiary collects it once.
If it does not, each pledger reclaims their own pledge. Nobody pays for an event that never happens.

## Lifecycle

| State     | Condition                                | What is possible                                              |
|-----------|------------------------------------------|---------------------------------------------------------------|
| Open      | `now <= deadline`                        | `pledge()` only. Nobody can collect or refund yet.            |
| Succeeded | `now > deadline` and `total >= target`   | `collect()` once, by anyone, pays the beneficiary. Refunds revert (`TargetMet`). |
| Failed    | `now > deadline` and `total < target`    | Each pledger calls `refund()` for their own pledge. `collect()` reverts. |
| Collected | `collected == true`                      | Nothing further.                                              |

Pledging and paying out never overlap: at exactly `deadline` pledging still works and payouts revert,
one second later it flips. `state()` returns the current state for UIs.

## Design decisions

- **Pull refunds.** `refund()` sends `msg.sender` their own recorded pledge. No function loops over pledgers,
  and no owner or beneficiary can trigger or block a refund.
- **Checks-effects-interactions plus a guard.** The pledge is zeroed and `totalPledged` reduced *before* the
  ETH is sent, and `refund()`/`collect()` also carry OpenZeppelin's `nonReentrant` (v5.7.0). Events are emitted before the external call.
- **One-shot payout.** `collect()` reads `collected`, sets it before the transfer, and reverts if the target is not met.
- **Immutable terms.** `beneficiary`, `target` and `deadline` are `immutable`, set only in the constructor.
  There is no owner and no setter.
- **Amounts come from `msg.value`.** `pledge()` is the only payable function; there is no `receive`/`fallback`.
- **No stuck funds.** Pledges are only accepted up to the deadline and payouts only after it, so ETH can't arrive after the campaign has paid out.
- **Raised total stays visible.** Refunds don't reduce `totalPledged`, so the page can still show what was raised after a failed campaign.

## Develop

```sh
forge build
forge test
```

The suite covers every state transition, both reentrancy paths (a malicious pledger and a malicious beneficiary),
and a fuzz test that refund and collect are mutually exclusive.

## Frontend

`frontend/` is a single static page (no build step, [viem](https://viem.sh) from a CDN) written for a student opening a
WhatsApp link on a phone. It shows the amount raised against the goal in ETH, a progress bar, time left, and a plain
sentence for each outcome. When a campaign fails it shows a red banner, the visitor's own pledge, and a **Claim my refund**
button. Contract errors are translated into plain English, and every action is simulated before the wallet is asked to sign.

Set the deployed address in `frontend/config.js`, then serve the folder:

```sh
cd frontend && python3 -m http.server 8000   # open http://localhost:8000 (or any static host)
```

It was exercised in a real browser against an anvil deployment through all four states, including pledge, refund, and
collect through the page.

## Verification performed

| Layer | Result |
|-------|--------|
| `forge test` | 36 tests pass, including exact-deadline boundary tests, 2 reentrancy attacks and a fuzz test |
| Slither | 0 findings; 4 accepted informational findings (`timestamp`, `low-level-calls`) are suppressed inline with a reason |
| Anvil smoke test | Success and failure paths behave as designed on deployed bytecode; the frontend was driven through Open, Failed (refund), Succeeded and Collected states in a browser |

## Deploy (Sepolia)

The signer is a Foundry keystore, never a file in this repo:

```sh
cast wallet import deployer --interactive
cp .env.example .env   # fill SEPOLIA_RPC_URL, BENEFICIARY, TARGET_WEI, DURATION_SECONDS
source .env
forge script script/Deploy.s.sol --rpc-url "$SEPOLIA_RPC_URL" --account deployer --broadcast
```

### Deployed address

| Network | Address |
|---------|---------|
| Sepolia | _pending deployment_ |
