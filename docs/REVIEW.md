# Local review scope

Production scope: `src/LaunchToken.sol` and the imported, vendored OpenZeppelin ERC-20
v5.2.0 dependency subset. There are no application contracts or hooks in `src/`.
The constructor's only addition to ERC-20 is a single mint of `10^27` minor units to
its deploying caller and the fixed name/symbol.

Review observations:

- Only holders can directly transfer or approve their balances. Delegated transfers
  require the holder's allowance for that specific spender. Neither the factory nor the
  protocol owner bypasses allowance checks.
- The constructor mints once to the factory, not to `tx.origin` or a hardcoded recipient.
  Inherited `_mint` and `_burn` are internal and have no runtime entrypoint in `LaunchToken`.
- Transfers use the original ERC-20 accounting. Self-transfers preserve balance and
  finite approvals decrease even when an approved transfer returns to the same holder.
  Zero addresses revert. EVM reverts roll back allowance spending if a later balance or
  recipient check fails. The tests exercise these boundaries explicitly.
- There are no external calls in the token, recipient hooks, delegatecalls, upgrade paths,
  initializers, owner roles, tax collectors, time-dependent paths, dynamic lists or oracles.
  Reentrancy, price manipulation and randomness are not mechanisms used by this token.
- The constructor has no arguments and does not rely on another deployed contract.
  It is compatible with factory deployment on an empty chain. The constructor's caller
  receives the full supply; the factory is responsible for all subsequent allocation.
- Plain transfers impose no pool-address check, purchase limit, max wallet or cooldown.
  The 1.25% pool fee belongs to the launch protocol and never changes ERC-20 accounting.
- Standard ERC-20 approval ordering and infinite-allowance risks remain. There is no
  recovery path for mistakenly sent tokens or forced ETH; no privileged rescue was added.
- The logo is a literal opaque crop of the requested photograph. Off-chain metadata
  supplies all branding fields with an embedded copy of the final PNG. No hosted image URL,
  token address or deployment status is invented.

Local checks comprise compilation with the pinned Solidity 0.8.26 settings, unit and
fuzz tests, stateful balance/supply/allowance invariants, a bounded-runtime/opcode scan,
format checking, metadata validation and vendored-file checksum verification.

These checks are not an independent security audit. Slither and Mythril were not run here.
The supplied protected owner test relies on verifier-owned `OwnerChecks.sol`; the
protected token/project harnesses rely on verifier-generated deployment/environment data.
They remain the independent verifier's responsibility. Local tests exercise the equivalent
token supply, factory-caller, transfer, runtime and absent-admin properties without
depending on those inputs or reading the environment.

Release review must check the actual manifest, deployed artifact, policy fee, the 9000
basis-point pool allocation, empty application-contract list and metadata handoff. This
project does not test or attest the live factory, LP custody, AMM, reward claims, chain
sequencer or explorer ingestion. No live deployment was performed as part of local review.
