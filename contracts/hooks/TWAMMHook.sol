// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IHooks} from '../interfaces/IHooks.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {ITWAMM} from '../interfaces/ITWAMM.sol';
import {Hooks} from '../libraries/Hooks.sol';
import {TickMath} from '../libraries/TickMath.sol';
import {TransferHelper} from '../libraries/TransferHelper.sol';
import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';
import {OrderPool} from '../libraries/TWAMM/OrderPool.sol';
import {BaseHook} from './base/BaseHook.sol';

contract TWAMMHook is BaseHook {
    using TWAMM for TWAMM.State;
    using TransferHelper for IERC20Minimal;

    uint256 public immutable expirationInterval;
    mapping(bytes32 => TWAMM.State) internal twammStates;
    mapping(address => mapping(address => uint256)) public tokensOwed;

    constructor(IPoolManager _poolManager, uint256 _expirationInterval) BaseHook(_poolManager) {
        expirationInterval = _expirationInterval;
        Hooks.validateHookAddress(
            this,
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
    }

    function lastVirtualOrderTimestamp(bytes32 key) external view returns (uint256) {
        return twammStates[key].lastVirtualOrderTimestamp;
    }

    function getOrder(IPoolManager.PoolKey calldata poolKey, TWAMM.OrderKey calldata orderKey)
        external
        view
        returns (TWAMM.Order memory)
    {
        return twammStates[keccak256(abi.encode(poolKey))].getOrder(orderKey);
    }

    function getOrderPool(IPoolManager.PoolKey calldata key, bool zeroForOne)
        external
        view
        returns (uint256 sellRateCurrent, uint256 earningsFactorCurrent)
    {
        TWAMM.State storage twamm = getTWAMM(key);
        return
            zeroForOne
                ? (twamm.orderPool0For1.sellRateCurrent, twamm.orderPool0For1.earningsFactorCurrent)
                : (twamm.orderPool1For0.sellRateCurrent, twamm.orderPool1For0.earningsFactorCurrent);
    }

    function getTokensOwed(address token, address owner) external view returns (uint256 amount) {
        return tokensOwed[token][owner];
    }

    function beforeInitialize(
        address,
        IPoolManager.PoolKey calldata key,
        uint160
    ) external virtual override poolManagerOnly returns (bytes4) {
        // Dont need to enforce one-time as each pool can only be initialized once in the manager
        getTWAMM(key).initialize();
        return BaseHook.beforeInitialize.selector;
    }

    function beforeModifyPosition(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata
    ) external override poolManagerOnly returns (bytes4) {
        executeTWAMMOrders(key);
        return BaseHook.beforeModifyPosition.selector;
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata
    ) external override poolManagerOnly returns (bytes4) {
        executeTWAMMOrders(key);
        return BaseHook.beforeSwap.selector;
    }

    struct CallbackData {
        address sender;
        IPoolManager.PoolKey key;
        IPoolManager.SwapParams params;
    }

    function executeTWAMMOrders(IPoolManager.PoolKey memory key) public {
        (uint160 sqrtPriceX96, , ) = poolManager.getSlot0(key);
        TWAMM.State storage twamm = getTWAMM(key);
        (bool zeroForOne, uint160 sqrtPriceLimitX96) = twamm.executeTWAMMOrders(
            poolManager,
            key,
            TWAMM.PoolParamsOnExecute(sqrtPriceX96, poolManager.getLiquidity(key)),
            expirationInterval
        );

        if (sqrtPriceLimitX96 != 0 && sqrtPriceLimitX96 != sqrtPriceX96) {
            poolManager.lock(abi.encode(key, IPoolManager.SwapParams(zeroForOne, type(int256).max, sqrtPriceLimitX96)));
        }
    }

    /// @notice Submits a new long term order into the TWAMM. Also executes TWAMM orders if not up to date.
    /// @param key The PoolKey for which to identify the amm pool of the order
    /// @param orderKey The OrderKey for the new order
    /// @param amountIn The amount of sell token to add to the order. Some precision on amountIn may be lost up to the
    /// magnitude of (orderKey.expiration - block.timestamp)
    /// @return orderId The bytes32 ID of the order
    function submitLongTermOrder(
        IPoolManager.PoolKey calldata key,
        TWAMM.OrderKey memory orderKey,
        uint256 amountIn
    ) external returns (bytes32 orderId) {
        TWAMM.State storage twamm = getTWAMM(key);
        executeTWAMMOrders(key);

        unchecked {
            // checks done in TWAMM library
            uint256 duration = orderKey.expiration - block.timestamp;
            uint256 sellRate = amountIn / duration;
            orderId = twamm.submitLongTermOrder(orderKey, sellRate, expirationInterval);
            IERC20Minimal(orderKey.zeroForOne ? key.token0 : key.token1).safeTransferFrom(
                msg.sender,
                address(this),
                sellRate * duration
            );
        }
    }

    /// @notice Modify an existing long term order with a new sellAmount
    /// @param key The PoolKey for which to identify the amm pool of the order
    /// @param orderKey The OrderKey for which to identify the order
    /// @param amountDelta The delta for the order sell amount. Negative to remove from order, positive to add, or
    ///    min value to remove full amount from order.
    function updateLongTermOrder(
        IPoolManager.PoolKey memory key,
        TWAMM.OrderKey memory orderKey,
        int256 amountDelta
    ) external returns (uint256 tokens0Owed, uint256 tokens1Owed) {
        executeTWAMMOrders(key);
        // This call reverts if the caller is not the owner of the order
        (uint256 buyTokensOwed, uint256 sellTokensOwed) = getTWAMM(key).updateLongTermOrder(orderKey, amountDelta);

        if (orderKey.zeroForOne) {
            tokens0Owed += sellTokensOwed;
            tokens1Owed += buyTokensOwed;
        } else {
            tokens0Owed += buyTokensOwed;
            tokens1Owed += sellTokensOwed;
        }

        tokensOwed[address(key.token0)][orderKey.owner] += tokens0Owed;
        tokensOwed[address(key.token1)][orderKey.owner] += tokens1Owed;
    }

    /// @notice Claim earnings from an ongoing or expired order
    /// @param token The token to claim
    /// @param to The receipient of the claim
    /// @param amountRequested The amount of tokens requested to claim
    /// @return amountTransferred The total token amount to be collected
    function claimTokens(
        IERC20Minimal token,
        address to,
        uint256 amountRequested
    ) external returns (uint256 amountTransferred) {
        uint256 currentBalance = token.balanceOf(address(this));
        amountTransferred = tokensOwed[address(token)][msg.sender];
        if (amountRequested != 0 && amountRequested < amountTransferred) amountTransferred = amountRequested;
        if (currentBalance < amountTransferred) amountTransferred = currentBalance; // to catch small precision errors
        token.safeTransfer(to, amountTransferred);
    }

    function lockAcquired(bytes calldata rawData) external override poolManagerOnly returns (bytes memory) {
        (IPoolManager.PoolKey memory key, IPoolManager.SwapParams memory swapParams) = abi.decode(
            rawData,
            (IPoolManager.PoolKey, IPoolManager.SwapParams)
        );

        IPoolManager.BalanceDelta memory delta = poolManager.swap(key, swapParams);

        if (swapParams.zeroForOne) {
            if (delta.amount0 > 0) {
                key.token0.safeTransfer(address(poolManager), uint256(delta.amount0));
                poolManager.settle(key.token0);
            }
            if (delta.amount1 < 0) {
                poolManager.take(key.token1, address(this), uint256(-delta.amount1));
            }
        } else {
            if (delta.amount1 > 0) {
                key.token1.safeTransfer(address(poolManager), uint256(delta.amount1));
                poolManager.settle(key.token1);
            }
            if (delta.amount0 < 0) {
                poolManager.take(key.token0, address(this), uint256(-delta.amount0));
            }
        }
        return bytes('');
    }

    function getTWAMM(IPoolManager.PoolKey memory key) private view returns (TWAMM.State storage) {
        return twammStates[keccak256(abi.encode(key))];
    }
}
