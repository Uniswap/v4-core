// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import './PoolManager.sol';

/// @notice Manages the balances for each pool
contract Vault {
    PoolManager public immutable manager;

    constructor(PoolManager _manager) {
        manager = _manager;
    }
}
