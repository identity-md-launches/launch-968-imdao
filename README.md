# IMDAO


## Community website — Soft Studio

The continuation adds a working React / TypeScript / Vite frontend in `web/` and a complete production export in `dist/`. The site is a local, demo-only preview. Contracts, contract tests, existing configuration, dependency locks, vendored libraries and original licenses are unchanged. No deployment or wallet interaction took place.

### Install, develop and rebuild

Use Node 22.12+ and npm. From the repository root:

```sh
cd web
npm ci
npm run dev
```

The development server binds to `127.0.0.1`. To validate and produce the repository-root export:

```sh
cd web
npm run typecheck
npm run build
npm run preview
```

Run these blocks separately from the repository root. `npm run preview` serves the production build locally, normally at `http://127.0.0.1:4173`. The checked-in export also needs no npm installation to preview:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory dist
```

Open `http://127.0.0.1:4173/`. Keep the same origin and port to reopen that browser’s saved drafts. Installing packages may use the network; after populating an npm cache, `npm ci --offline` works from the supplied lockfile. This was checked using an isolated build directory. No dependency cache or `node_modules` directory is delivered. Rollup is pinned through the new frontend manifest’s override because the automatically resolved 4.64.2 reproducibly stalled this Vite build; 4.46.2 builds successfully.

### What works

- `#/` and `#/ideas`: community example cards, text search, category and status filters, an empty-results state, idea details and illustrative discussions.
- `#/projects` and `#/projects/:id`: demo project scope, owner status, milestones and linked ideas/decisions. Completed fixtures are explicitly not real completed work.
- `#/vote` and `#/vote/:id`: read-only governance examples, the actual prototype lifecycle and four allowed action types. No vote, queue, execution or submission action exists in this frontend.
- `#/treasury`: development/reserve examples, available/reserved/paid values and separate principal returns/proceeds, all labeled in MockAsset units. Live values say “Not connected”.
- `#/draft/new`, `#/draft/new?template=:id`, `#/draft/:id`, `#/drafts`: four curated starters, blank drafts, editable preview, local save/reopen/edit/delete, validation and storage recovery. Business starters include customers, cost assumptions and receipt reporting. A proposed operator and budget start unspecified.
- Sage Light and Graphite Dark follow the system until manually selected; a separate versioned preference persists when storage is available. The pre-render theme bootstrap avoids a wrong-theme first paint.

Drafts are private browser data, saved only after an explicit action. Required fields are title, problem/opportunity and first step. Unspecified fields remain visible as incomplete. Navigation, replacement, browser Back and reload protect unsaved work. Delete/reset require native confirmation. A storage failure never reports success. Clearing browser data can remove drafts; save separate copies of important text. This is not encrypted storage and there is no cross-device synchronization.

### Source and data

`web/src/data.ts` contains typed templates, ideas, projects, governance and treasury fixtures with explicit IDs and demo provenance. Drafts have local provenance and retain `sourceTemplateId`. `storage.ts` validates versioned data, field lengths/types, duplicate IDs and budget units, and caps storage at 60 drafts / 2,000,000 serialized characters. Corrupt data is preserved until an explicit reset. Theme storage uses `imdao.theme.v1`; drafts use a version-1 envelope under `imdao.drafts.v1`.

`App.tsx` contains the shared shell and hash router, `pages.tsx` the read-only views, `Editor.tsx` the local editor, and `components.tsx` shared interface primitives. All inputs render as text. [DESIGN.md](DESIGN.md) records the implemented tokens, exact logo geometry, full local IBM Plex Mono font and responsive behavior. Asset and guidance notices ship under `web/public/licenses/` and `dist/licenses/`.

### Checks and screenshots

Production build, TypeScript check and an offline lockfile install passed. Browser checks use a temporary local server at `/preview/` and installed Chromium through Playwright. The script owns and closes both its browser and server; it does not deploy the site. [Validation and six-domain review](docs/frontend/validation.md) documents actual results, fixes and limitations. [Machine-readable results](docs/frontend/interaction-results.json) and [build log](docs/frontend/build.log) retain evidence.

To reproduce browser checks, install the check tools separately from the application, then run from the repository root:

```sh
npm install --prefix /tmp/imdao-browser-tools playwright axe-core@4.10.3
/tmp/imdao-browser-tools/node_modules/.bin/playwright install chromium
IMDAO_PLAYWRIGHT_MODULE=/tmp/imdao-browser-tools/node_modules/playwright/index.mjs \
IMDAO_AXE_SCRIPT=/tmp/imdao-browser-tools/node_modules/axe-core/axe.min.js \
node web/checks/browser.mjs
```

An existing Chromium binary may be selected with `IMDAO_CHROMIUM=/absolute/path/to/chromium`. The worker used the preinstalled Chromium headless shell because the browser connector was unavailable. Exact worker commands and tool versions are in the validation record.

Screenshots: [desktop light](docs/frontend/desktop-light.png), [desktop dark](docs/frontend/desktop-dark.png), [mobile light](docs/frontend/mobile-light.png), [mobile dark](docs/frontend/mobile-dark.png). Additional editor and keyboard-focus captures accompany these in `docs/frontend/`.

Evidence is retained under `docs/frontend/` for repository review. The network output copies remain under `artifacts/`, which the supplied workspace excludes from Git. After re-running checks, refresh the corresponding evidence copies in `docs/frontend/`.

### Publishing and later integration

No public publication was performed. When separately authorized, publish the **contents of `dist/`**, preserving its `assets/`, `fonts/` and `licenses/` directories. The publisher should use this finished export, not rebuild it. Vite uses `base: './'`, all runtime assets are local and relative, and hash routes work at a static gateway subpath without rewrite rules. Do not publish `web/`, private drafts, dependency caches or development tooling as the site.

Backend/onchain integration and an independent security review are future work. There is no database, authentication, API, wallet connection, transaction construction, autonomous posting, funding, paid service or live revenue. The governance descriptions come from the existing source: enrollment, constrained payouts, selection between two pinned fee policies, and a mock oracle request. An idea is not a formal proposal; votes and executed payments do not establish completion.

This workspace task forbids modifying `.git/`, so no commit or deployment was made by the worker. The contributor network must capture `web/`, `dist/`, `DESIGN.md`, this README and `docs/frontend/` in its submission commit. Existing `REVIEW.sha256` is retained as a historical record. Its README entry predates this continuation, and 23 vendored-library entries already differed from the workspace at task start. It is not a clean checksum of the accepted tree; this frontend task does not regenerate that contract-review artifact. A separate comparison against the actual start-of-task files confirms that only README.md changed among pre-existing files. See the integrity record in `docs/frontend/`.

---

## Local Foundry prototype

**Source-only, valueless fixtures. Nothing has been deployed, signed, funded, or connected to a live service. This is not launch-ready or audited.**

The project implements a fixed-supply Votes token, restricted governance and timelock, recipient enrollment, a two-bucket cash treasury, a real local Uniswap v4 PoolManager/router/hook integration, two immutable policies, and an authenticated mock evidence oracle. Production contracts are in `src/`; malicious actors, simplified accounting fixtures, and all setup are in `test/`.

## Reproduce offline

Requires Foundry and **solc 0.8.26** already installed. The compiler version, optimizer settings, and **Cancun** EVM are pinned in `foundry.toml`. Cancun is needed for v4 transient storage. All imported Solidity dependencies are ordinary vendored files in `lib/`; there are no package downloads, submodules, or network calls during tests.

```sh
forge fmt --check
forge build
forge test
forge lint src --severity high
```

Optional focused runs:

```sh
forge test --match-contract FeesTest -vv
forge test --match-contract GovernanceTest -vv
forge test --match-contract PayoutsTest -vv
forge test --match-contract TreasuryAccountingTest -vv
forge test --match-contract 'AccountingInvariantTest|SwapInvariantTest' -vv
forge test --match-path test/OraclePolicies.t.sol -vv
```

Tests do not use environment, FFI, filesystem, RPC, forks, network, broadcast, or key/signature cheatcodes. They use isolated EVM state, locally created contracts, named fixture addresses, block/time controls, and targeted fault injection. `test/scratch/` is unnecessary to build or run the delivered project.

Dependency revisions and included subsets are recorded in [dependencies.lock.json](dependencies.lock.json). Original licenses are retained under each library. See [docs/VERIFICATION.md](docs/VERIFICATION.md) for recorded checks, test coverage, and static-analysis limitations. The compiler-generated public interfaces are delivered in [docs/abi/](docs/abi/); `forge inspect Treasury abi` regenerates one interface.

## Contracts, roles, and fixed wiring

| Contract | Responsibility and authority |
| --- | --- |
| `IMDAO` | OZ ERC20Votes, name/symbol IMDAO, 18 decimals, exactly 1,000,000 whole tokens minted in constructor. No subsequent mint, tax, rebase, blacklist, or pause. Block-number checkpoints. |
| `MockIMD` | Separate 18-decimal ERC20Votes fixture with constructor-only 1,000,000 supply. Delegated identity voting power only; never a treasury asset. |
| `MockAsset` | Valueless 18-decimal ERC20 pair asset, constructor-only 1,000,000 supply. |
| `RestrictedGovernor` | Proposals from qualified delegates; votes from historical delegates; restricted queue and cancellation accounting. Anyone may trigger queue after a proposal succeeds. |
| `RestrictedTimelock` | Governor is sole proposer/canceller; anyone executes. Delay fixed at 3,600 seconds; admin is the timelock itself. No role/delay setter or generic call facility. |
| `Treasury` | Recipient registry and asset/bucket accounting. Timelock alone enrolls/disables/pays; only recipient accepts enrollment or sends business receipts; guardian only suspends. Governor alone binds IDs and reserves/releases cash/caps. Hook alone credits fees. |
| `FeeHook` | Fixed manager, PoolId, currencies, treasury, fee, and policy runtimes. Only timelock activates one of the two pinned policies. Only authenticated manager callbacks for its exact pool are accepted. |
| `FixtureRouter` | Open swaps and position-specific LP actions through the real manager. Caller supplies its own funding, limits and LP salt; no arbitrary payer field. |
| `PolicyV1` / `PolicyV2` | Direct pure 80/20 and 60/40 development/reserve weights. No storage, proxy, or external dependency. |
| `MockOracle` / `MockDelivery` | Timelock requests evidence, immutable delivery authenticates its fixture responder, and anyone expires a pending request after timeout. Evidence confers no votes or action authority. |

Only policy selection and recipients change. Token, treasury, hook, supported assets, pool, caps, voting formula, fee, and authority wiring do not. There is no owner/AI bypass, proxy, delegatecall, generic call dispatcher, trading pause, sweep, conversion, outgoing treasury approval, LP-principal claim, reward or buyback. The separate frontend described above is a local preview only.

The real local PoolManager's owner is the restricted timelock. Its administrative selectors are outside the governor's allowlist, so the local fixture cannot enable a protocol-fee controller through governance.

### Local construction order and parameters

`test/helpers/Fixture.sol::setUp` is the executable fixture specification, not a public deployment script:

1. Construct IMDAO, MockIMD and MockAsset to the test contract; distribute and delegate to several named local accounts.
2. Construct timelock with the fixture bootstrap; construct the real v4 PoolManager with the timelock as its owner.
3. Construct treasury with explicit bootstrap, timelock, guardian, manager and the two supported assets. It requires distinct ERC20 contracts reporting 18 decimals.
4. Mine a local CREATE2 salt for hook flags **0x2044** and construct the hook with LP fee **3000 / 1,000,000 (30 bps)** and tick spacing **60**. The hook constructs and pins V1 and V2 itself; initial policy is V1. PoolKey sorts the two token addresses and includes this hook.
5. Construct router, delivery with a fixture responder, oracle, then governor referencing the existing contracts. No predicted cyclic constructor references or reinitializable contracts are needed.
6. Bootstrap calls `treasury.freeze(governor, hook, router)` and `timelock.freeze(governor)`. These verify dependency getters, mark system destinations, and irreversibly erase bootstrap authority. No trading/proposals before frozen wiring. Repeated or unauthorized freezing fails.
7. Initialize the fixed pool at `sqrtPriceX96 = 2**96`, then add valueless liquidity of `5_000_000e18` liquidity units over ticks `[-600, 600]` with caller budgets of `200_000e18` each. Liquidity units are not token amounts or additional minted supply.

Fixture voters receive the following whole units and self-delegate **both** tokens. Remaining tokens stay with the fixture holder, initially undelegated, including funds for LP activity.

| Voter | IMDAO | MockIMD |
| --- | ---: | ---: |
| Alice | 60,000 | 40,000 |
| Bob | 40,000 | 1,000 |
| Carol | 35,000 | 30,000 |
| Dave | 10,000 | 0 |
| IMD-only delegate | 0 | 200,000 |

Guardian, responder and business recipient are named local fixtures. Recipients start unapproved. No address, key, token, metadata, or fixture amount in these tests is a launch decision.

## Governance and voting

`propose(target, value, data, purpose, text, sources)` requires **10,000e18 base IMDAO votes at block.number - 1** and value zero. Purpose, text and source-link strings are frozen in the creation event and committed as `descriptionHash = keccak256(abi.encode(purpose, text, sources))`. Their sizes are bounded. The proposal ID commits to chain ID, governor, target, zero value, canonical calldata, and this description hash. Duplicate IDs cannot be reused or edited.

Exactly one action is permitted:

```solidity
hook.activatePolicy(address candidate, bytes32 codeHash)
treasury.setRecipient(address recipient, uint256 expectedVersion, bool enabled, bytes32 metadataHash)
treasury.pay(bytes32 paymentId, address asset, uint8 bucket, address recipient,
             uint256 version, uint256 amount, bytes32 purposeHash)
oracle.request(bytes32 questionHash)
```

Target and selector must both match. Exact lengths and decode/re-encode equality reject trailing data, noncanonical encodings, malformed data and batches. Timelock self-calls, role changes, delay changes, unrelated selectors and nonzero value are impossible. The timelock dispatches typed calls to these fixed targets; it never uses `target.call`.

For a proposal made at block B, snapshot is **B+1**, deadline **snapshot+100**, and voting is allowed at **snapshot < block.number <= deadline** (100 blocks). Both tokens use the same historical snapshot:

```text
C = IMDAO.getPastVotes(delegate, snapshot)
I = MockIMD.getPastVotes(delegate, snapshot)
weight = C + min(floor(C / 4), I)
```

Amounts are 18-decimal base units. IMD alone gives zero; the maximum bonus is 25%. Transfers/redelegation after the snapshot cannot move votes for that proposal. `support` is 0 AGAINST, 1 FOR, 2 ABSTAIN; one vote per delegate per proposal. Separate base and weighted three-entry tallies are exposed. Success requires **base FOR + base ABSTAIN >= 40,000e18** and **weighted FOR > weighted AGAINST**. AGAINST does not contribute to quorum; ties fail.

Proposal states: Unknown → Pending → Active → Defeated/Succeeded → Queued → Executed. The original proposer may cancel in any unexecuted known state, even after losing voting power. Queued payment proposals additionally allow anyone to cancel when expired or when their bound recipient version/status is invalid. Nonpayments do not expire. Creation, vote, queue, cancellation and timelock execution events plus `proposal`, `state`, `operation`, `status`, `hasVoted` and `votingPower` expose the lifecycle. Direct timelock execution updates the state seen through governor views.

## Recipients and payments

`setRecipient` checks the **current expectedVersion**, increments it, commits the operator/purpose metadata hash, and clears acceptance. Enabling creates PendingAcceptance; only that exact recipient may `accept(version)` to become Active. Disabling creates Disabled at execution. Guardian `suspend(recipient)` increments version immediately and sets Suspended. Guardian cannot enroll, accept, spend, cancel governance, change policy or pause trading. Re-enabling requires a fresh governance proposal and fresh acceptance. Suspension invalidates stale enrollment proposals as well as payouts.

Nonzero, non-system recipients must already be Active at the matching version at **proposal, queue and execution**. System exclusions include treasury, manager, router, hook, both assets, MockIMD, governor, timelock, bootstrap, guardian, policies, oracle, delivery and responder. Replacing a recipient/operator needs fresh enrollment and a new payout proposal; existing payout terms cannot be changed.

Payment constraints:

- Nonzero permanent paymentId, positive amount, supported asset, bucket **0 development / 1 reserve**, and nonzero purposeHash.
- ID binds to one proposal and tuple forever, including after failure, cancellation or return.
- Queue atomically reserves available asset/bucket cash and lifetime cap capacity, then schedules the timelock. Failed scheduling/reservation rolls back the entire transaction.
- Per asset, across **all buckets**, `grossPaid + reserved <= 10,000e18` per recipient and `<= 100,000e18` globally. No cross-asset valuation, cap resets or netting after returns/re-enrollment.
- `readyAt = queue timestamp + 3600`; `expiresAt = readyAt + 604800`.
- Timelock alone pays the exact reserved tuple at **readyAt <= now < expiresAt**, after rechecking recipient status/version. It consumes the reservation and bucket, increases gross paid, and transfers once. Failure rolls back operation status, accounting and token state for retry or cancellation.
- Cancellation cancels the timelock operation and releases cash and both cap reservations atomically; it never releases gross-paid usage. Expiry/status invalidation does not release capacity until someone calls `governor.cancel(id)`.
- No batch expiry loop or replay. Each milestone needs another proposal and vote.

A return or later proof of business success cannot authorize a future payment. Off-chain reviewers must check recipients, budgets, purpose and milestone evidence before voting. Allowlisting proves neither honesty nor signer continuity; hashes only bind submitted descriptions.

## Surcharge and policies

The hook uses only beforeInitialize, afterSwap and afterSwapReturnDelta permissions; there are no LP hooks. Manager and the complete PoolId are authenticated. Its surcharge is:

```text
fee = floor(abs(unspecified raw swap delta) * 25 / 10000)
```

This is an additional **25 bps on the unspecified delta**, on top of the pool's LP fee, with an immutable 25-bps cap. It is **not verified IMD creator fees**. No live fee integration is claimed.

| Direction/mode | Unspecified asset | Effect of positive hook return delta |
| --- | --- | --- |
| token0 → token1, exact input | token1 output | Trader receives raw output minus surcharge |
| token1 → token0, exact input | token0 output | Trader receives raw output minus surcharge |
| token0 → token1, exact output | token0 input | Trader pays raw input plus surcharge |
| token1 → token0, exact output | token1 input | Trader pays raw input plus surcharge |

Magnitude is widened before negating to handle int128 minimum safely. The return delta is positive. The router checks final input/output signs and limits after this delta, enforcing min output and max input for both modes and rejecting partial exact-output fills. Exact-input partial fills can succeed only within the caller's price/output limits.

Treasury measures manager and treasury balances around a single-use hook callback to `manager.take(currency, treasury, amount)`. Only the fixed hook can credit the exact receipt. No estimate or ERC6909 claim enters spendable accounting. **Manager must already have enough settled cash during afterSwap**, particularly for the input-asset exact-output surcharge. Pre-funding sits at the router until settlement. Insufficient manager cash reverts the whole swap; deferred claims/pre-settlement funding are not implemented.

`development = floor(receipt * developmentBps / 10000)` and reserve receives the remainder. V1 is 8000/2000, V2 6000/4000. Both deployed addresses and expected runtime hashes are pinned from the compiled pure contract types, checked on activation and reading. The reader makes a **30,000-gas STATICCALL**, copies at most **64 bytes**, requires exactly two words and weights summing to 10000, and defaults to built-in 80/20 on invalid output, revert, missing/changed code, or exhausted call gas. V2 affects only future fees; existing bucket balances and reservations do not move. Neither policy can change fees, custody, recipients or old balances.

The router pulls only from **msg.sender before unlock**, checks exact pre-funding debit/credit, and settles using its own tokens. Callback data contains no payer or recipient address. A reentrancy guard spans pull, unlock, settlement and refund; callback additionally checks the real manager, active entry guard, and a single-use payload hash. LP salt is `keccak256(abi.encode(msg.sender, userSalt))`. Refunds/outputs go to the initiating caller and exclude the router's pre-existing balance. Donations to the router cannot be spent as someone else's budget.

## Business receipts and accounting

Only the original recipient of a **Paid** payment may call:

```solidity
returnUnspent(bytes32 paymentId, uint256 amount, bytes32 evidenceHash)
depositProceeds(bytes32 paymentId, uint256 amount, bytes32 evidenceHash)
```

This remains allowed while suspended or disabled. Recipient grants an ERC20 allowance **into** the treasury. The treasury pulls a positive amount of the original asset, checks exact sender debit and treasury credit, then accounts it in the original bucket. The implementation records effects before the external transfer under a reentrancy guard; any failure rolls back those effects. Each accepted receipt gets a unique chain/consumer/nonce/payment/evidence/type-bound ID. Evidence hashes are nonzero and globally single-use across return/proceeds receipts.

Cumulative returns cannot exceed the original payout. Proceeds are uncapped and recorded separately. Returns are recipient-declared unspent funds; proceeds are **not audited profit**. Neither reduces lifetime gross cap usage, edits the payment, converts currencies, proves business/fiat/tax performance, or grants a clawback right.

For each supported asset:

```text
fees + returns + proceeds - grossPayments = development + reserve
reservedInBucket <= bucket
sum(bucket reservations) = global reserved cap capacity
cash >= development + reserve
surplus = cash - development - reserve
```

Reservations are **included in buckets**, not additional liabilities. Raw transfers/donations are unallocated surplus; there is no way to convert surplus into spendable income or sweep it. Only exact transfer semantics are accepted. SafeERC20 accommodates optional return data, while taxed, false-return, rebasing-style credit/debit changes, or failing transfers revert atomically. No unsupported token is admitted later and treasury cannot approve tokens outward.

## Mock oracle state machine

The mock intentionally differs from the supplied **live** IdentityMD oracle reference. The task asks for no live API, live IMD, fees, keys, or protocol signatures. This is an immutable local delivery/responder trust fixture, not a live protocol implementation; it does not include or claim live attestation conformance.

Timelock-only `request(questionHash)` increments a nonce and creates `keccak256(abi.encode(nonce, chainid, consumer, questionHash))`. Exactly one request may be Pending; timeout is 3600 seconds and payment zero. Request state is Unknown/Pending/Answered/Expired; answer is independently UNKNOWN/NO/YES. No answer always remains UNKNOWN.

Only immutable MockDelivery may call `onAnswer(bytes)`, and delivery only accepts its immutable fixture responder. The envelope is **exactly 192 bytes**, canonical ABI encoding of:

```solidity
(bytes32 requestId, uint256 chainId, address consumer,
 bytes32 questionHash, bool answer, bytes32 evidenceHash)
```

It must match the pending request, recorded/current chain, consumer and question, contain nonzero evidence, and arrive at **now < expiry**. Wrong senders, malformed booleans/lengths, forged domains/IDs/questions, duplicates and late answers fail. False answers are stored as NO, never reverted. Anyone calls `expire(id)` at **now >= expiry**; retries are fresh requests authorized by fresh governance actions. An already queued distinct proposal may execute after the old request is answered or explicitly expired. Callback only stores evidence and emits an event; no spending, upgrade, extra call or voting effect exists, and oracle activity is absent from swap/LP paths.

## Responsibilities and unresolved production gates

A separate independent adversarial review must precede any future use with value. That work must decide and validate:

- Real operator identity, multisig membership, signer continuity, recipient metadata and purpose evidence; the registry cannot establish them.
- Guardian multisig selection, monitoring, suspension criteria, key security and liveness. In this immutable prototype guardian loss is permanent; there is no rotation route.
- Budget/cap suitability, treasury runway, per-asset exposure and fresh votes for every milestone; returns/proceeds are declarations, not accounting/audit automation.
- Real IMD chain, checkpoints or escrow, decimal normalization, cross-chain proofs, delegated-power versus beneficial ownership, borrowing/flash-loan risk and checkpoint timing. The fixture bonus is **delegated MockIMD power, not verified live holdings**.
- Live IMD fee/hook compatibility, chain-specific v4 contracts and address mining, cash availability during afterSwap, router compatibility, price limits, LP economics and user slippage. No live creator-fee claim has been verified.
- Live oracle protocol/delivery/signature conformance, authorization, service fees, liveness, truth/evidence definitions and operational response. Mock answers are no truth proof.
- Immutable-contract migration, any new governance/policy design, incident response and independent review. There is no general migration or rescue route in this prototype, and immutable settings cannot be silently patched.

There is no “after launch” configuration or launch manifest: this assignment authorizes only source and local fixtures. Do not use test addresses or parameters for a launch. No public deployment, wallet control, transaction signing or funding is part of the deliverable.

`REVIEW.sha256` freezes the delivered source/dependency/interface/document contents for review. **No Git commit was created because the assignment forbids touching `.git/`.** The contributor network must capture this checksum-verified snapshot in its review commit. Rebuilding ABIs or changing any file requires a new snapshot and review.
