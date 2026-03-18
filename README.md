# Uniswap v4 Core

[![Lint](https://github.com/Uniswap/v4-core/actions/workflows/lint.yml/badge.svg)](https://github.com/Uniswap/v4-core/actions/workflows/lint.yml)
[![Tests](https://github.com/Uniswap/v4-core/actions/workflows/tests-merge.yml/badge.svg)](https://github.com/Uniswap/v4-core/actions/workflows/tests-merge.yml)

Uniswap v4 is an automated market maker protocol that provides extensible and customizable pools. `v4-core` hosts the core pool logic for creating pools and executing pool actions like swapping and providing liquidity.

Uniswap v4 is live on Ethereum, Polygon, Arbitrum, OP Mainnet, Base, BNB Chain, Blast, World Chain, Avalanche, and Zora Network. The codebase has undergone [nine independent audits](https://docs.uniswap.org) and maintains a [$15.5M bug bounty](https://uniswap.org/bug-bounty) — the largest in DeFi history.

For a detailed technical description, see the [Uniswap v4 Core Whitepaper](https://github.com/Uniswap/v4-core/tree/main/docs/whitepaper-v4.pdf). For higher-level contracts, see the [v4-periphery](https://github.com/Uniswap/v4-periphery) repository.

> **Contributing:** Uniswap v4 was built in public with open feedback and meaningful community contribution. We welcome contributions of any size. See our [contribution guidelines](./CONTRIBUTING.md) to get started.

## Architecture

v4-core uses a singleton-style architecture, where all pool state is managed in the `PoolManager.sol` contract. Pool actions can be taken after an initial call to `unlock`.

Only the net balances owed to the pool (positive) or to the user (negative) are tracked throughout the duration of an unlock. This is the `delta` field held in the unlock state. Any number of actions can be run on the pools, as long as the deltas accumulated during the unlock reach 0 by the unlock's release. This unlock and call style architecture gives callers maximum flexibility in integrating with the core code.

Additionally, a pool may be initialized with a **hook contract**, that can implement any of the following callbacks in the lifecycle of pool actions:

- beforeInitialize / afterInitialize
- beforeAddLiquidity / afterAddLiquidity
- beforeRemoveLiquidity / afterRemoveLiquidity
- beforeSwap / afterSwap
- beforeDonate / afterDonate

The callback logic may be updated by the hooks dependent on their implementation. However, which callbacks are executed on a pool cannot change after pool initialization.

## Repository Layout

All contracts are held within the `v4-core/src` folder. Note that helper contracts used by tests are held in the `v4-core/src/test` subfolder within the `src` folder. Any new test helper contracts should be added here, but all foundry tests are in the `v4-core/test` folder.

```
src/
├── interfaces/
│   ├── IPoolManager.sol
│   └── ...
├── libraries/
│   ├── Position.sol
│   ├── Pool.sol
│   └── ...
├── test/
└── PoolManager.sol

test/
└── libraries/
    ├── Position.t.sol
    └── Pool.t.sol
```

## Local Development

To utilize the contracts and deploy to a local testnet, you can install the code in your repo with forge:

```bash
forge install https://github.com/Uniswap/v4-core
```

## Using Solidity Interfaces

The Uniswap v4 interfaces are available for import into solidity smart contracts via the `v4-core` package, e.g.:

```solidity
import {IPoolManager} from 'v4-core/contracts/interfaces/IPoolManager.sol';
import {IUnlockCallback} from 'v4-core/contracts/interfaces/callback/IUnlockCallback.sol';

contract MyContract is IUnlockCallback {
    IPoolManager poolManager;

    function doSomethingWithPools() {
        // this function will call `unlockCallback` below
        poolManager.unlock(...);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        // disallow arbitrary caller
        if (msg.sender != address(poolManager)) revert Unauthorized();

        // perform pool actions
        poolManager.swap(...)
    }
}

error Unauthorized();
```

## Security

This repository is subject to the Uniswap v4 bug bounty program. See [SECURITY.md](./SECURITY.md) for reporting guidelines, or submit directly through the [Uniswap bug bounty](https://uniswap.org/bug-bounty).

**Audits:**

| Auditor | Report |
|---------|--------|
| OpenZeppelin | [v4-core audit](https://blog.openzeppelin.com/uniswap-v4-core-audit) |

For the complete list of audit reports, see the [Uniswap v4 documentation](https://docs.uniswap.org).

## Documentation

- [Uniswap v4 Documentation](https://docs.uniswap.org) — Full technical docs, guides, and API reference
- [v4-periphery](https://github.com/Uniswap/v4-periphery) — Peripheral contracts including hooks and position managers
- [Contributing](./CONTRIBUTING.md) — How to contribute to v4-core
- [Security](./SECURITY.md) — Bug bounty and vulnerability reporting

## Licensing

Uniswap V4 Core is licensed under the Business Source License 1.1 (`BUSL-1.1`), see [`BUSL_LICENSE`](./BUSL_LICENSE), and the MIT License (`MIT`), see [`MIT_LICENSE`](./MIT_LICENSE).

Each file in Uniswap V4 Core states the applicable license type in the header.
