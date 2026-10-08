# Local verification and review notes

These are the implementer's observations, not an independent audit or authority to deploy.

## Toolchain and reproducibility

- Foundry 1.8.3 (`cae51ad458f6abb64852b7709eb784352429825d`).
- solc **0.8.26**, Cancun, optimizer 200 runs, via IR; bytecode metadata hash disabled. Configuration is in `foundry.toml`.
- Solidity dependencies are vendored ordinary files, pinned by commit in `dependencies.lock.json`, with retained licenses. Only the source dependency closure is needed.
- No FFI/filesystem permissions. No test environment, RPC, fork, network, signing or broadcast calls. Each test constructs isolated local fixtures.
- `forge fmt --check`, `forge build` and `forge test` completed successfully on the final tree.
- `forge test --offline --threads 4` also passed all 58 groups, demonstrating the vendored tree needs no dependency fetch and runs concurrently.
- `forge build --sizes --skip test` passed; all source contracts fit runtime/initcode size limits (largest source runtime: Treasury, 14,146 bytes).
- Foundry reports **58 passed, 0 failed, 0 skipped**, across ten suites. This Foundry version groups the two accounting invariant functions into one reported test group.
- Fuzz functions run **256 cases** each. Both invariant campaigns use **64 runs × 64 calls = 4,096 calls**, with zero handler reverts. The accounting handler includes a successful payout/return/proceeds/cancel prelude, then interleaves both assets, both buckets, fees, payments, receipts, cancellation, suspension and re-enrollment.

## Coverage map

| Suite | Evidence |
| --- | --- |
| `FeesTest` | Four real PoolManager direction/exactness cases; mathematical surcharge/sign/currency checks against final deltas; fuzz amounts/directions/modes; slippage rollback; permission bits and wrong manager/PoolId; LP ownership and exits while recipient suspended; actual insufficient-manager-cash failure; surplus; victim allowance protection; V2 future-only splitting. |
| `GovernanceTest` | Fixed supply, delegation and block clock; threshold at prior block; IMD-only zero power; immutable description hash; canonical selector/target/value rejection; snapshots after transfers/redelegation; bonus floor/cap fuzz; double votes; base quorum, AGAINST exclusion, ABSTAIN inclusion, weighted majority and tie; bootstrap removal and forbidden roles; open direct execution, nonpayment lifetime and proposer cancellation. |
| `PayoutsTest` | Enrollment before proposals, recipient-only current acceptance, stale enrollment race, guardian invalidation, disabling, new-version acceptance; system/zero addresses and invalid fields; atomic queues, cash/cap reservations and failure; direct timelock ready/expiry boundaries; public cancellation; permanent IDs; failed transfer retry/replay; receipts while suspended, evidence uniqueness, allowance failure rollback, proceeds, return and re-spending. |
| `TreasuryAccountingTest` | Isolated ledger fixture with a real token-moving fee vault; exact recipient/global caps across buckets and assets, both reserved and paid capacity; no cap reset on return/re-enrollment; tuple immutability; target time/status checks; rejection, tax, extra debit, bonus credit and false returns; optional empty transfer return data; attempted reentrant payout; proceeds/surplus/conservation; no outgoing approvals. The simplified authority harness exists only in tests, never in src. |
| `RouterFaultsTest` | Real manager with a deliberately adversarial supported-token replacement: exact caller pre-funding, taxed/false/nonstandard failure rollback, rejected reentrant swap/callback attempts, SafeERC20 empty-return token compatibility. Such replaceable behavior is test fault injection; normal fixtures have no token mutation switches. |
| `OracleTest` | Zero payment and deterministic nonce/domain-bound request IDs; pending UNKNOWN, stored false/true answers; sender, size, boolean, request, chain, consumer and question authentication; duplicate/late rejection; one pending; exact timeout and fresh governance retry; no responder voting authority. |
| `PolicyFaultsTest`, `PolicyPinningTest` | Bad hash/candidate/changed runtime; V2 activation; missing code, revert, truncated/extra/huge return data, gas exhaustion, STATICCALL mutation rejection, weight fuzz and fallback. Reader fault injection is separate from pinning tests because malformed arbitrary policies cannot be activated. |
| `AccountingInvariantTest` | Independent ghost totals versus all on-chain ledgers, bucket conservation, exact cash plus surplus, reservation limits, lifetime caps, immutable payment history and bounded returns across randomized sequences. |
| `SwapInvariantTest` | Randomized real-manager swap sequences in all four cases, exact cash-backed treasury accounting, no treasury surplus created by swaps and no user funds left at the router. |

## Static analysis

`forge lint src --severity high` produced **no findings**. Forge's built-in lint analysis was available and ran. Slither and Mythril were **not installed** and were not run; a successful Forge lint pass is not a substitute for either or for independent review.

Medium/low lint findings remain visible; none are globally suppressed. Reviewer triage:

| Pattern | Why present / review boundary |
| --- | --- |
| Strict equality on token balances | Intentional exact **change** verification using fresh before/after snapshots. It rejects tax/rebase/false movement and does not compare against a fixed expected total balance that donations could permanently invalidate. Reservation availability uses inequalities. Donations remain surplus. |
| Reentrancy around SafeERC20, manager or typed timelock dispatch | Entry points use OZ ReentrancyGuard, CEI and atomic rollback. Router intentionally keeps the entry lock held through its authenticated callback, consuming the callback hash before external actions. Fee collection uses the treasury lock plus the hook lock and a consumed fee tuple. Tests attempt reentry. Forge also warns about the guard's own post-call `_status` reset. This requires independent control-flow review, not blind suppression. |
| Timestamps | Explicit 3600-second timelock/oracle windows and seven-day payment window; inclusive/exclusive boundaries have tests. They are deadlines, not randomness or price inputs. |
| Zero-check heuristics | Contract-address arguments are validated with `.code.length > 0`, wiring getter checks, and asset decimals. EOA fixture authority arguments explicitly reject zero. Cleared bootstrap storage is intentionally zero after freezing. |
| Event/access-control heuristics | Bootstrap erasure and system-address enrollment are covered by WiringFrozen/Frozen events; registry changes have version/status/metadata events. Some lint heuristics do not associate compound wiring effects with these events. |

### Previous rejection addressed

The previous attempt allowed a callback-supplied `sender` to reach `transferFrom(sender, manager, amount)`. In this tree, **the only router transferFrom is `safeTransferFrom(msg.sender, address(this), amount)` in entry pre-funding**. Callback `_settle` transfers router-owned funds and has no payer parameter. The callback is manager-only, checks the active entry guard, and consumes the hash of the entry's encoded action. It cannot be invoked directly to spend a victim allowance. Tests leave an unrelated voter's allowance intact and attempt token-triggered reentry. LP salts are bound to the initiating caller, so a caller cannot remove another caller's router position.

SafeCast now checks signed/unsigned/narrow conversions in hook/router. Timelock schedule, cancellation and execution are guarded; treasury reserve, cancellation, payout, fee collection and business receipts are guarded. Standard fixed-supply assets are still the supported production-code assumption; adversarial tests do not mean arbitrary ERC20 contracts are safe.

## Snapshot and remaining review work

`REVIEW.sha256` records all delivered source, tests, dependency files, ABI exports and documentation. Check it with `sha256sum -c REVIEW.sha256`. No `.git/` changes or commit were made because the task forbids them. The contributor network should capture the verified files as the frozen independent-review commit, without inputs under `.imd/`, generated `out/`/`cache/`, or scratch tests.

All prototype trust and production gates remain open as described in README. In particular: live IMD voting/checkpoints/escrow/chain/decimals and borrowing resistance, authentic fee integration, v4 cash timing, live oracle conformance/truth/liveness, budgets, operator/multisig/guardian governance, immutable migration, and independent adversarial review. No deploy, signature, wallet funding, or claim of launch readiness is authorized by these checks.
