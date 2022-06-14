// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';
import {IPoolManager} from './IPoolManager.sol';

interface ITWAMM {
    function submitLongTermOrder(
        IPoolManager.PoolKey calldata key,
        TWAMM.OrderKey calldata orderKey,
        uint256 amountIn
    ) external returns (bytes32 orderId);

    function updateLongTermOrder(
        IPoolManager.PoolKey calldata key,
        TWAMM.OrderKey calldata orderKey,
        int256 amountDelta
    ) external returns (uint256 tokens0Owed, uint256 tokens1Owed);

    function executeTWAMMOrders(IPoolManager.PoolKey memory key) external;

    function tokensOwed(address token, address owner) external returns (uint256);
}
