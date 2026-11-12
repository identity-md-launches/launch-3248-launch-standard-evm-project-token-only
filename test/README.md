# XLONGDOG test coverage

The original `LaunchToken.t.sol` and `LaunchToken.invariant.t.sol` remain intact.
The additional suites exercise the actual `src/LaunchToken.sol`, including its
vendored ERC-20 implementation. No production source, dependency or configuration
changes are needed. All Solidity tests run offline.

`LaunchToken.Adversarial.t.sol` adds deterministic boundary cases and six fuzz
properties (1,000 cases each, configured in the file):

- Exact one-unit transfers, repeated transfer round trips, and split-versus-single
  transfers, with no tax or rounding loss.
- Approval exhaustion, replay after refunding the holder, revocation of infinite
  approvals, the finite `uint256.max - 1` boundary, and independent owner/spender pairs.
- Failed delegated spending followed by funding and a successful retry, proving
  the failed operation did not consume the approval.
- Actual contract recipients and callers, including an approved transaction origin
  behind an unapproved relay. Receiver callbacks must not run.
- Properly encoded dynamic admin/metadata probes, native-ETH rejection at all
  three mutable entrypoints, zero-address failures, and zero-value transfer events.
- Full-supply transfers after arbitrary bounded time and block advances.

`LaunchToken.Stateful.t.sol` adds a handler with four funded actors, including the
token's deploying contract. It drives 12 explicitly selected actions in random
order for 256 sequences of depth 96. Actions include successful direct/delegated
transfers, approvals, round trips, unsolicited transfers to the token itself,
and deliberately invalid balance/allowance/zero-address/mint/burn calls. Inputs
explicitly visit zero, one unit, full balances, and finite/infinite approval edges.

The handler keeps an independent ledger initialized from the specified constructor
supply and updated from requested operations. Bounds come from this ledger, not
the token's reported balances. After every action, invariants compare every actor's
balance and every tracked allowance against the ledger, conserve exactly `10^27`
minor units including donations held by the token, and preserve the token identity.
Failures check exact revert data and unchanged accounting immediately. Expected
token reverts are caught; unexpected handler reverts fail under the existing project
configuration. No revert-filtering configuration is added.

An end-of-sequence check moves each actor's entire balance to a collector and then
moves the combined balance again. This checks transfer liveness after adversarial
history. It accounts separately for unsolicited token-contract balances; it does
not impersonate the token to recover those balances. A deterministic handler
exercise verifies that successful delegated calls and every failure action are
reachable, including both finite and infinite approval branches. Its counters
exclude constructor fixture activity.

## Property discovery

The five supplied Pashov discovery perspectives were applied locally, together
with the Trail of Bits guidance on input bounds, non-vacuity and failure triage,
and the supplied Foundry testing reference. No helper agents or external fuzzers
were used. These are requirement-backed properties, not speculative assertions.

| Perspective | Property and evidence | Coverage |
| --- | --- | --- |
| Conservation | The requested fixed supply equals all balances; each successful transfer preserves it. `LaunchToken.sol:13` mints once; vendored `ERC20.sol:183` updates balances. | Independent ledger, all recipient accounting, fixed-supply invariant |
| State transitions | Approvals replace one owner/spender pair; finite spending consumes permission, infinite spending preserves it; failed calls roll back. `ERC20.sol:149`, `:280`, `:301`. | Approval lifecycle fuzzing and success/failure handler actions |
| Round trips and rounding | The requested plain transfers must return the exact original amount and be independent of splitting. There is no runtime conversion or division in `ERC20.sol:183`. | Repeated direct/delegated round trips, split-versus-single property, one-unit boundary |
| Adversarial value extraction and liveness | No caller, including the deployer, can mint or bypass holder approval; valid full-balance transfers remain possible. `LaunchToken.sol:12`, `ERC20.sol:104`, `:149`. | Relay identity tests, valid admin calldata, rejection actions, end-of-sequence sweep |
| Token-specific semantics | Zero/self transfers preserve balances, zero recipients cannot burn, allowances are isolated, and contract recipients need no hooks. `ERC20.sol:104`, `:166`, `:210`. | Exact event tests, self-transfer actions, zero-address failures, contract caller probe |

Vault shares, interest, oracle pricing, withdrawal queues, and pool conversion
rounding do not exist in this token and have no invented properties here.

## Verification and boundaries

Run from the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x0ae142c4d582cfc7c2e720ebe4475ede0acc6e4752c8e2f0c76b673eb5f53f37 forge test
python3 tools/metadata.py
```

For the restricted contributor workspace, build artifacts and cache can be kept
inside disposable scratch space by prefixing the Foundry commands with
`FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache`.
This changes output locations only. The tests do not read or modify environment
variables, use FFI, require filesystem permissions, or use RPC endpoints.

The existing metadata checker was also run: it checks the exact bio and website/X
fields, the embedded image, and the opaque 512-pixel PNG and original-photo hashes.
Those assets are not embedded again in a Solidity test, which would only test a
copy and would not validate the delivered files.

The repository contains the token, not ProjectFactory, the AMM, or MerkleDistributor.
The original 90/10 split test establishes token transfer compatibility only. It
cannot establish that a future manifest actually sets `economics.poolBps = 9000`,
uses an empty application-contract list, or that the live factory seeds the pool.
No fork block or deployment was supplied for this tests assignment, and no fork
was run. Manifest admission, actual launch allocation, LP custody, reward claims,
and explorer/website publication remain deployment-stage checks. No Solidity
defect was reproduced by these tests.
