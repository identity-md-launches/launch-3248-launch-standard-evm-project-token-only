# Vendored Solidity dependencies

All dependency source is included as ordinary files. No installation or submodule update
is required. `SHA256SUMS` records each vendored file relative to the repository root.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | `v5.2.0` | ERC20, IERC20, IERC20Metadata, Context, draft-IERC6093 and LICENSE | MIT |
| forge-std | `v1.9.6` | Entire upstream `src/` plus LICENSE-MIT and LICENSE-APACHE | MIT / Apache-2.0 |

Upstream release sources:

- https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.2.0
- https://github.com/foundry-rs/forge-std/tree/v1.9.6

Only the OpenZeppelin ERC-20 dependency subset is imported into production code. The
OpenZeppelin files are unmodified; no extensions or externally linked libraries are used.
forge-std is test support only. Its source includes helpers for many kinds of projects;
this project's tests never invoke filesystem access, FFI, environment configuration, forks,
signing or broadcast helpers.
