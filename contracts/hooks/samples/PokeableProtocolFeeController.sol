// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IProtocolFeeController} from '../../interfaces/IProtocolFeeController.sol';
import {IPoolManager} from '../../interfaces/IPoolManager.sol';
import {Pool} from '../../libraries/Pool.sol';

contract PokeableProtocolFeeController is IProtocolFeeController {
    IPoolManager poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function fetchInitialFee(IPoolManager.PoolKey memory key) external view returns (uint8) {
        return 0;
    }

    function propagateProtocolFee(IPoolManager.PoolKey memory fromKey, IPoolManager.PoolKey memory toKey) external {
        // require the "to" pool exists (dont need to check "from" as protocol fee will do that)
        (uint160 toSqrtPriceX96, , uint8 toProtocolFee) = poolManager.getSlot0(toKey);
        require(toSqrtPriceX96 != 0);

        // only propagates the protocol fee from one with non 0 fee to one with a 0 fee
        (, , uint8 fromProtocolFee) = poolManager.getSlot0(fromKey);

        require(toProtocolFee == 0 && fromProtocolFee != 0);

        // Check that the overall fee of the "to" pool is within 10%
        (uint24 smallerFee, uint24 largerFee) = (fromKey.fee > toKey.fee)
            ? (toKey.fee, fromKey.fee)
            : (fromKey.fee, toKey.fee);

        require((10 * uint256(largerFee - smallerFee)) / smallerFee == 0);

        poolManager.setPoolProtocolFee(toKey, fromProtocolFee);
    }
}
