# Meetup Assurance Contract

An all-or-nothing assurance contract for funding a meetup: **the meetup only happens if we all chip in.**
People pledge ETH before a deadline. If the pledged total reaches the target, the beneficiary collects it once.
If it does not, each pledger reclaims their own pledge. Nobody pays for an event that never happens.

## Lifecycle

```
            pledge() until deadline
   Open ───────────────────────────────┐
    │                                  ▼
    │  total >= target           total < target
    ▼                                  ▼
 Funded ── collect() (once) ──▶ Collected     Failed ── refund() per pledger ──▶ Refunded
```

| State     | Condition                              | What is possible                                   |
|-----------|----------------------------------------|----------------------------------------------------|
| Open      | `now <= deadline`                      | `pledge()`; `refund()` while total < target        |
| Funded    | `totalPledged >= target`               | `collect()` once; `refund()` reverts (`TargetMet`) |
| Collected | `collected == true`                    | nothing further; `pledge()` reverts                |
| Failed    | `now > deadline` and total < target    | `refund()`; `pledge()` reverts (`DeadlinePassed`)  |

## Design decisions

- **Pull refunds.** `refund()` sends `msg.sender` their own recorded pledge. No function loops over pledgers,
  and no owner or beneficiary can trigger or block a refund.
- **Checks-effects-interactions plus a guard.** The pledge is zeroed and `totalPledged` reduced *before* the
  ETH is sent, and `refund()`/`collect()` also carry a `nonReentrant` modifier.
- **One-shot payout.** `collect()` reads `collected`, sets it before the transfer, and reverts if the target is not met.
- **Immutable terms.** `beneficiary`, `target` and `deadline` are `immutable`, set only in the constructor.
  There is no owner and no setter.
- **Amounts come from `msg.value`.** `pledge()` is the only payable function; there is no `receive`/`fallback`.
- **No stuck funds.** `pledge()` reverts once the campaign is collected.

## Develop

```sh
forge build
forge test
```

The suite covers every state transition, both reentrancy paths (a malicious pledger and a malicious beneficiary),
and a fuzz test that refund and collect are mutually exclusive.

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
