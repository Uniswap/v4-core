// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ProtocolFees} from "../ProtocolFees.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {Currency} from "../types/Currency.sol";
import {PoolId} from "../types/PoolId.sol";
import {Pool} from "../libraries/Pool.sol";
import {Slot0} from "../types/Slot0.sol";

contract ProtocolFeesImplementation is ProtocolFees {
    mapping(PoolId id => Pool.State) internal _pools;
    bool internal isUnlocked;

    constructor() ProtocolFees(msg.sender) {}

    // Used to set the price of a pool to pretend that the pool has been initialized in order to successfully set a protocol fee
    function setPrice(PoolKey memory key, uint160 sqrtPriceX96) public {
        Pool.State storage pool = _getPool(key.toId());
        pool.slot0 = pool.slot0.setSqrtPriceX96(sqrtPriceX96);
    }

    function _getPool(PoolId id) internal view override returns (Pool.State storage) {
        return _pools[id];
    }

    function setIsUnlocked(bool newValue) public {
        isUnlocked = newValue;
    }

    function _isUnlocked() internal view override returns (bool) {
        return isUnlocked;
    }

    function updateProtocolFees(Currency currency, uint256 amount) public {
        ProtocolFees._updateProtocolFees(currency, amount);
    }
}
