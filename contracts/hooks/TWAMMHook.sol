// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

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

contract TWAMMHook is BaseHook, ITWAMM {
    using TWAMM for TWAMM.State;
    using TransferHelper for IERC20Minimal;

    // Time interval on which orders are allowed to expire. Conserves processing needed on execute.
    uint256 public immutable expirationInterval;
    // twammStates[poolId] => Twamm.State
    mapping(bytes32 => TWAMM.State) internal twammStates;
    // tokensOwed[token][owner] => amountOwed
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
        bytes32 poolId = keccak256(abi.encode(key));
        (uint160 sqrtPriceX96, , ) = poolManager.getSlot0(poolId);
        TWAMM.State storage twamm = twammStates[poolId];

        (bool zeroForOne, uint160 sqrtPriceLimitX96) = twamm.executeTWAMMOrders(
            poolManager,
            key,
            TWAMM.PoolParamsOnExecute(sqrtPriceX96, poolManager.getLiquidity(poolId)),
            expirationInterval
        );

        if (sqrtPriceLimitX96 != 0 && sqrtPriceLimitX96 != sqrtPriceX96) {
            poolManager.lock(abi.encode(key, IPoolManager.SwapParams(zeroForOne, type(int256).max, sqrtPriceLimitX96)));
        }
    }

    /// @inheritdoc ITWAMM
    function submitLongTermOrder(
        IPoolManager.PoolKey calldata key,
        TWAMM.OrderKey memory orderKey,
        uint256 amountIn
    ) external returns (bytes32 orderId) {
        bytes32 poolId = keccak256(abi.encode(key));
        TWAMM.State storage twamm = twammStates[poolId];
        executeTWAMMOrders(key);

        uint256 sellRate;
        unchecked {
            // checks done in TWAMM library
            uint256 duration = orderKey.expiration - block.timestamp;
            sellRate = amountIn / duration;
            orderId = twamm.submitLongTermOrder(orderKey, sellRate, expirationInterval);
            IERC20Minimal(orderKey.zeroForOne ? key.token0 : key.token1).safeTransferFrom(
                msg.sender,
                address(this),
                sellRate * duration
            );
        }

        emit SubmitLongTermOrder(
            poolId,
            orderKey.owner,
            orderKey.expiration,
            orderKey.zeroForOne,
            sellRate,
            twamm.getOrder(orderKey).earningsFactorLast
        );
    }

    /// @inheritdoc ITWAMM
    function updateLongTermOrder(
        IPoolManager.PoolKey memory key,
        TWAMM.OrderKey memory orderKey,
        int256 amountDelta
    ) external returns (uint256 tokens0Owed, uint256 tokens1Owed) {
        bytes32 poolId = keccak256(abi.encode(key));
        TWAMM.State storage twamm = twammStates[poolId];

        executeTWAMMOrders(key);

        // This call reverts if the caller is not the owner of the order
        (uint256 buyTokensOwed, uint256 sellTokensOwed, uint256 newSellrate, uint256 newEarningsFactorLast) = twamm
            .updateLongTermOrder(orderKey, amountDelta);

        if (orderKey.zeroForOne) {
            tokens0Owed += sellTokensOwed;
            tokens1Owed += buyTokensOwed;
        } else {
            tokens0Owed += buyTokensOwed;
            tokens1Owed += sellTokensOwed;
        }

        tokensOwed[address(key.token0)][orderKey.owner] += tokens0Owed;
        tokensOwed[address(key.token1)][orderKey.owner] += tokens1Owed;

        emit UpdateLongTermOrder(
            poolId,
            orderKey.owner,
            orderKey.expiration,
            orderKey.zeroForOne,
            newSellrate,
            newEarningsFactorLast
        );
    }

    /// @inheritdoc ITWAMM
    function claimTokens(
        IERC20Minimal token,
        address to,
        uint256 amountRequested
    ) external returns (uint256 amountTransferred) {
        uint256 currentBalance = token.balanceOf(address(this));
        amountTransferred = tokensOwed[address(token)][msg.sender];
        if (amountRequested != 0 && amountRequested < amountTransferred) amountTransferred = amountRequested;
        if (currentBalance < amountTransferred) amountTransferred = currentBalance; // to catch precision errors
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
