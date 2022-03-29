// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';
import {IPoolManager} from './IPoolManager.sol';

interface ITWAMM {
    function submitLongTermOrder(IPoolManager.PoolKey calldata key, TWAMM.LongTermOrderParams calldata params)
        external
        returns (uint256 orderId);

    function cancelLongTermOrder(IPoolManager.PoolKey calldata key, uint256 orderId)
        external
        returns (uint256 amountOut0, uint256 amountOut1);

    function executeTWAMMOrders(IPoolManager.PoolKey memory key)
        external
        returns (IPoolManager.BalanceDelta memory delta);
}
