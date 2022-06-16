// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';
import {IPoolManager} from './IPoolManager.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

interface ITWAMM {
    /// @notice Emitted when a new long term order is submitted
    /// @param poolId The id of the corresponding pool
    /// @param owner The owner of the new order
    /// @param expiration The expiration timestamp of the order
    /// @param zeroForOne Whether the order is selling token 0 for token 1
    /// @param sellRate The sell rate of tokens per second being sold in the order
    /// @param earningsFactorLast The current earningsFactor of the order pool
    event SubmitLongTermOrder(
        bytes32 indexed poolId,
        address indexed owner,
        uint160 expiration,
        bool zeroForOne,
        uint256 sellRate,
        uint256 earningsFactorLast
    );

    /// @notice Emitted when a long term order is updated
    /// @param poolId The id of the corresponding pool
    /// @param owner The owner of the existing order
    /// @param expiration The expiration timestamp of the order
    /// @param zeroForOne Whether the order is selling token 0 for token 1
    /// @param sellRate The updated sellRate of tokens per second being sold in the order
    /// @param earningsFactorLast The current earningsFactor of the order pool
    ///   (since updated orders will claim existing earnings)
    event UpdateLongTermOrder(
        bytes32 indexed poolId,
        address indexed owner,
        uint160 expiration,
        bool zeroForOne,
        uint256 sellRate,
        uint256 earningsFactorLast
    );

    /// @notice Submits a new long term order into the TWAMM. Also executes TWAMM orders if not up to date.
    /// @param key The PoolKey for which to identify the amm pool of the order
    /// @param orderKey The OrderKey for the new order
    /// @param amountIn The amount of sell token to add to the order. Some precision on amountIn may be lost up to the
    /// magnitude of (orderKey.expiration - block.timestamp)
    /// @return orderId The bytes32 ID of the order
    function submitLongTermOrder(
        IPoolManager.PoolKey calldata key,
        TWAMM.OrderKey calldata orderKey,
        uint256 amountIn
    ) external returns (bytes32 orderId);

    /// @notice Update an existing long term order with current earnings, optionally modify the amount selling.
    /// @param key The PoolKey for which to identify the amm pool of the order
    /// @param orderKey The OrderKey for which to identify the order
    /// @param amountDelta The delta for the order sell amount. Negative to remove from order, positive to add, or
    ///    -1 to remove full amount from order.
    function updateLongTermOrder(
        IPoolManager.PoolKey calldata key,
        TWAMM.OrderKey calldata orderKey,
        int256 amountDelta
    ) external returns (uint256 tokens0Owed, uint256 tokens1Owed);

    /// @notice Claim tokens owed from TWAMMHook contract
    /// @param token The token to claim
    /// @param to The receipient of the claim
    /// @param amountRequested The amount of tokens requested to claim. Set to 0 to claim all.
    /// @return amountTransferred The total token amount to be collected
    function claimTokens(
        IERC20Minimal token,
        address to,
        uint256 amountRequested
    ) external returns (uint256 amountTransferred);

    function executeTWAMMOrders(IPoolManager.PoolKey memory key) external;

    function tokensOwed(address token, address owner) external returns (uint256);
}
