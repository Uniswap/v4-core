# Uniswap Protocol

[![Lint](https://github.com/Uniswap/core-next/actions/workflows/lint.yml/badge.svg)](https://github.com/Uniswap/core-next/actions/workflows/lint.yml)
[![Tests](https://github.com/Uniswap/core-next/actions/workflows/tests.yml/badge.svg)](https://github.com/Uniswap/core-next/actions/workflows/tests.yml)
[![Mythx](https://github.com/Uniswap/core-next/actions/workflows/mythx.yml/badge.svg)](https://github.com/Uniswap/core-next/actions/workflows/mythx.yml)
[![npm version](https://img.shields.io/npm/v/@uniswap/core-next/latest.svg)](https://www.npmjs.com/package/@uniswap/core-next/v/latest)

This repository contains the smart contracts for the Uniswap Protocol.

## Local deployment

In order to deploy this code to a local testnet, you should install the npm package
`@uniswap/core-next`
and import the factory bytecode located at
`@uniswap/core-next/artifacts/contracts/PoolManager.sol/PoolManager.json`.
For example:

```typescript
import {
  abi as FACTORY_ABI,
  bytecode as FACTORY_BYTECODE,
} from '@uniswap/core-next/artifacts/contracts/PoolManager.sol/PoolManager.json'

// deploy the bytecode
```

This will ensure that you are testing against the same bytecode that is deployed to
mainnet and public testnets, and all Uniswap code will correctly interoperate with
your local deployment.

## Using solidity interfaces

The Uniswap v3 interfaces are available for import into solidity smart contracts
via the npm artifact `@uniswap/core-next`, e.g.:

```solidity
import '@uniswap/core-next/contracts/interfaces/IPoolManager.sol';

contract MyContract {
  IPoolManager pool;

  function doSomethingWithPool() {
    // pool.swap(...);
  }
}

```
