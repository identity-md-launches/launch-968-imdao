# Public ABIs

These JSON arrays are compiler-generated ABIs of the delivered `src/` contracts using the pinned solc 0.8.26 configuration. They include constructors, public functions/views, events, and errors; no addresses are encoded. They are interface artifacts, not deployment artifacts or a compatibility claim for a live protocol.

Regenerate any ABI from the repository root:

```sh
forge inspect src/Treasury.sol:Treasury abi --json > docs/abi/Treasury.json
```

`IMDAO.json`, `MockIMD.json`, and `MockAsset.json` originate in `src/IMDAO.sol`; policies originate in `src/Policies.sol`; oracle and delivery originate in `src/MockOracle.sol`. Other filenames match their source contract.

State enum values:

| Type | Values in numeric order |
| --- | --- |
| Governor State | Unknown, Pending, Active, Defeated, Succeeded, Queued, Executed, Cancelled |
| Timelock Status | Unknown, Scheduled, Done, Cancelled |
| RecipientStatus | Unapproved, PendingAcceptance, Active, Disabled, Suspended |
| PaymentStatus | Unknown, Proposed, Reserved, Paid, Cancelled |
| Oracle Status | Unknown, Pending, Answered, Expired |
| Oracle Answer | UNKNOWN, NO, YES |

Vote support: 0 AGAINST, 1 FOR, 2 ABSTAIN. Treasury bucket: 0 development, 1 reserve. All token quantities are 18-decimal base units; timestamps are Unix seconds; voting snapshots/deadlines are block numbers.

Proposal creation events preserve original purpose/text/source strings, while proposal storage exposes their immutable hash. Treasury's `payment(id)` returns the full reserved/paid tuple and history; `proposal(id)` returns base and weighted tally arrays. For exact lifecycle semantics and authority boundaries see the root README.
