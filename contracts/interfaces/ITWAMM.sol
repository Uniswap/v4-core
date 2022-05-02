// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';
import {IPoolManager} from './IPoolManager.sol';

interface ITWAMM {
    function submitLongTermOrder(IPoolManager.PoolKey calldata key, TWAMM.LongTermOrderParams calldata params)
        external
        returns (bytes32 orderId);

    function claimEarningsOnLongTermOrder(IPoolManager.PoolKey calldata key, TWAMM.OrderKey calldata orderKey)
        external
        returns (uint256 earningsAmount);

    function modifyLongTermOrder(
        IPoolManager.PoolKey calldata key,
        TWAMM.OrderKey calldata orderKey,
        int128 amountDelta
    ) external returns (uint256 amountOut0, uint256 amountOut1);

    function executeTWAMMOrders(IPoolManager.PoolKey memory key) external;
}
