// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import { CurrencyDelta } from "src/libraries/CurrencyDelta.sol";
import { IPoolManager } from "src/interfaces/IPoolManager.sol";
import { PoolManager } from "src/PoolManager.sol";
import { Currency } from "src/types/Currency.sol";

contract CurrencyDeltaTest is PoolManager {
    constructor(address initialOwner) PoolManager(initialOwner) {}

    function getDelta(Currency currency, address target) external view returns (int256) {
        return CurrencyDelta.getDelta(currency, target);
    }

    function applyDelta(Currency currency, address target, int128 delta)
        external
        returns (int256, int256)
    {
        return CurrencyDelta.applyDelta(currency, target, delta);
    }
}