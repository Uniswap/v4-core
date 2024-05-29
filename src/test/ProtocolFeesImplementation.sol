// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ProtocolFees} from "../ProtocolFees.sol";
import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {Currency} from "../types/Currency.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {Pool} from "../libraries/Pool.sol";
import {Slot0} from "../types/Slot0.sol";

contract ProtocolFeesImplementation is ProtocolFees {
    using PoolIdLibrary for PoolKey;

    mapping(PoolId id => Pool.State) internal _pools;

    constructor(uint256 _controllerGasLimit) ProtocolFees(_controllerGasLimit) {}

    // Used to set the price of a pool to pretend that the pool has been initialized in order to successfully set a protocol fee
    function setPrice(PoolKey memory key, uint160 sqrtPriceX96) public {
        Pool.State storage pool = _getPool(key.toId());
        pool.slot0 = pool.slot0.setSqrtPriceX96(sqrtPriceX96);
    }

    function _getPool(PoolId id) internal view override returns (Pool.State storage) {
        return _pools[id];
    }

    function fetchProtocolFee(PoolKey memory key) public returns (bool, uint24) {
        return ProtocolFees._fetchProtocolFee(key);
    }

    function updateProtocolFees(Currency currency, uint256 amount) public {
        ProtocolFees._updateProtocolFees(currency, amount);
    }

    function consumeGasLimitAndFetchFee(PoolKey memory key) public {
        // consume gas before calling fetchProtocolFee / getting the protocolFeeForPool from the controller
        while (true) {
            // once gas left is less than the limit, stop consuming gas
            if (gasleft() < 9079256829993496519) {
                break;
            }
        }
        // fetch the protocol fee after consuming gas
        // will revert since the gas left is less than the limit
        fetchProtocolFee(key);
    }

    function consumeGasAndFetchFee(PoolKey memory key) public {
        while (true) {
            // consume just under the gas limit
            if (gasleft() < 9079256829993490000) {
                break;
            }
        }
        // try to fetch the protocol fee
        // will revert while fetching since the gas limit has been reached
        fetchProtocolFee(key);
    }
}
