// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Tick} from '../Tick.sol';
import {TickBitmap} from '../TickBitmap.sol';
import {IPoolManager} from '../../interfaces/IPoolManager.sol';
import {TickMath} from '../TickMath.sol';
import {OrderPool} from './OrderPool.sol';
import {TwammMath} from './TwammMath.sol';
import {FixedPoint96} from '../FixedPoint96.sol';
import {SqrtPriceMath} from '../SqrtPriceMath.sol';
import {SwapMath} from '../SwapMath.sol';
import {SafeCast} from '../SafeCast.sol';

/// @title TWAMM - Time Weighted Average Market Maker
/// @notice TWAMM represents long term orders in a pool
library TWAMM {
    using OrderPool for OrderPool.State;
    using TickMath for *;
    using SafeCast for *;
    using TickBitmap for mapping(int16 => uint256);

    bool constant ZERO_FOR_ONE = true;
    bool constant ONE_FOR_ZERO = false;

    /// @notice Thrown when account other than owner attempts to interact with an order
    /// @param orderId The orderId
    /// @param owner The owner of the order
    /// @param currentAccount The invalid account attempting to interact with the order
    error MustBeOwner(bytes32 orderId, address owner, address currentAccount);

    /// @notice Thrown when trying to cancel an already completed order
    /// @param orderId The orderId
    error OrderAlreadyCompleted(bytes32 orderId);

    /// @notice Thrown when trying to submit an order with an expiration that isn't on the interval.
    /// @param expiration The expiration timestamp of the order
    error ExpirationNotOnInterval(uint256 expiration);

    /// @notice Thrown when trying to submit an order with an expiration time in the past.
    /// @param expiration The expiration timestamp of the order
    error ExpirationLessThanBlocktime(uint256 expiration);

    /// @notice Thrown when trying to submit an order without initializing TWAMM state first
    error NotInitialized();

    /// @notice Thrown when trying to submit an order that's already ongoing.
    /// @param orderId The already existing orderId
    error OrderAlreadyExists(bytes32 orderId);

    /// @notice Thrown when trying to interact with an order that does not exist.
    /// @param orderId The already existing orderId
    error OrderDoesNotExist(bytes32 orderId);

    /// @notice Thrown when trying to subtract more value from a long term order than exists
    /// @param orderId The orderId
    /// @param unsoldAmount The amount still unsold
    /// @param amountDelta The amount delta for the order
    error InvalidAmountDelta(bytes32 orderId, uint256 unsoldAmount, int256 amountDelta);

    /// @notice Contains full state related to the TWAMM
    /// @member poolKey
    /// @member expirationInterval Interval in seconds between valid order expiration timestamps
    /// @member lastVirtualOrderTimestamp Last timestamp in which virtual orders were executed
    /// @member orderPools Mapping from bool zeroForOne to OrderPool that is selling zero for one or vice versa
    /// @member orders Mapping of orderId to individual orders
    struct State {
        uint256 lastVirtualOrderTimestamp;
        OrderPool.State orderPool0For1;
        OrderPool.State orderPool1For0;
        mapping(bytes32 => Order) orders;
    }

    /// @notice Information that identifies an order
    /// @member owner Owner of the order
    /// @member expiration Timestamp when the order expires
    /// @member zeroForOne Bool whether the order is zeroForOne
    struct OrderKey {
        address owner;
        uint160 expiration;
        bool zeroForOne;
    }

    /// @notice Information associated with a long term order
    /// @member zeroForOne Index of sell token, 0 for token0, 1 for token1
    /// @member expiration Timestamp when the order expires
    /// @member sellRate Amount of tokens sold per interval
    /// @member unclaimedEarningsFactor The accrued earnings factor from which to start claiming owed earnings for this order
    /// @member uncollectedEarningsAmount Earnings amount claimed thus far, but not yet transferred to the owner.
    struct Order {
        uint160 expiration;
        bool zeroForOne;
        uint256 sellRate;
        uint256 unclaimedEarningsFactor;
        uint256 uncollectedEarningsAmount;
    }

    /// @notice Initialize TWAMM state
    function initialize(State storage self) internal {
        self.lastVirtualOrderTimestamp = block.timestamp;
    }

    struct LongTermOrderParams {
        address owner;
        bool zeroForOne;
        uint256 amountIn;
        uint160 expiration;
    }

    /// @notice Submits a new long term order into the TWAMM
    /// @param params All parameters to define the new order
    function submitLongTermOrder(
        State storage self,
        LongTermOrderParams memory params,
        uint256 expirationInterval
    ) internal returns (bytes32 orderId) {
        if (self.lastVirtualOrderTimestamp == 0) revert NotInitialized();
        if (params.expiration < block.timestamp) revert ExpirationLessThanBlocktime(params.expiration);
        if (params.expiration % expirationInterval != 0) revert ExpirationNotOnInterval(params.expiration);

        bool zeroForOne = params.zeroForOne;
        orderId = _orderId(OrderKey(params.owner, params.expiration, zeroForOne));
        if (self.orders[orderId].sellRate != 0) revert OrderAlreadyExists(orderId);

        uint256 sellRate;
        OrderPool.State storage orderPool = zeroForOne ? self.orderPool0For1 : self.orderPool1For0;

        unchecked {
            sellRate = params.amountIn / (params.expiration - block.timestamp);
            orderPool.sellRateCurrent += sellRate;
            orderPool.sellRateEndingAtInterval[params.expiration] += sellRate;
        }

        self.orders[orderId] = Order({
            expiration: params.expiration,
            sellRate: sellRate,
            zeroForOne: zeroForOne,
            unclaimedEarningsFactor: orderPool.earningsFactorCurrent,
            uncollectedEarningsAmount: 0
        });
    }

    /// @notice Modify an existing long term order with a new sellAmount
    /// @param self The TWAMM State
    /// @param orderKey The OrderKey for which to identify the order
    /// @param amountDelta The delta for the order sell amount. Negative to remove from order, positive to add, or
    ///    min value to remove full amount from order.
    /// @return amountOut the amount of the order's sell token removed from the order
    function modifyLongTermOrder(
        State storage self,
        OrderKey memory orderKey,
        int128 amountDelta
    ) internal returns (uint256 amountOut) {
        bytes32 orderId = _orderId(orderKey);
        Order storage order = _getOrder(self, orderKey);
        if (orderKey.owner == address(0)) revert OrderDoesNotExist(orderId);
        if (orderKey.owner != msg.sender) revert MustBeOwner(orderId, orderKey.owner, msg.sender);
        if (order.expiration <= block.timestamp) revert OrderAlreadyCompleted(orderId);

        OrderPool.State storage orderPool = order.zeroForOne ? self.orderPool0For1 : self.orderPool1For0;

        unchecked {
            // cache existing earnings
            uint256 earningsFactor = orderPool.earningsFactorCurrent - order.unclaimedEarningsFactor;
            order.uncollectedEarningsAmount += (earningsFactor * order.sellRate) >> FixedPoint96.RESOLUTION;
            order.unclaimedEarningsFactor = orderPool.earningsFactorCurrent;

            uint256 unsoldAmount = order.sellRate * (order.expiration - block.timestamp);
            if (amountDelta == type(int128).min) amountDelta = -(unsoldAmount.toInt256().toInt128());
            int256 newSellAmount = unsoldAmount.toInt256() + amountDelta;
            if (newSellAmount < 0) revert InvalidAmountDelta(orderId, unsoldAmount, amountDelta);

            uint256 newSellRate = uint256(newSellAmount) / (order.expiration - block.timestamp);

            if (amountDelta < 0) {
                amountOut = uint256(uint128(-amountDelta));
                uint256 sellRateDelta = order.sellRate - newSellRate;
                uint256 amountOut = uint256(uint128(-amountDelta));
                orderPool.sellRateCurrent -= sellRateDelta;
                orderPool.sellRateEndingAtInterval[order.expiration] -= sellRateDelta;
            } else {
                uint256 sellRateDelta = newSellRate - order.sellRate;
                orderPool.sellRateCurrent += sellRateDelta;
                orderPool.sellRateEndingAtInterval[order.expiration] += sellRateDelta;
            }
            order.sellRate = newSellRate;
        }
    }

    /// @notice Claim earnings from an ongoing or expired order
    /// @param orderKey The key of the order to be claimed
    function claimEarnings(State storage self, OrderKey memory orderKey)
        internal
        returns (uint256 earningsAmount, bool zeroForOne)
    {
        bytes32 orderId = _orderId(orderKey);
        Order storage order = self.orders[orderId];
        zeroForOne = order.zeroForOne;
        OrderPool.State storage orderPool = zeroForOne ? self.orderPool0For1 : self.orderPool1For0;

        unchecked {
            if (block.timestamp >= order.expiration) {
                uint256 earningsFactor = orderPool.earningsFactorAtInterval[order.expiration] -
                    order.unclaimedEarningsFactor;
                earningsAmount = (earningsFactor * order.sellRate) >> FixedPoint96.RESOLUTION;
                order.sellRate = 0;
            } else {
                uint256 earningsFactor = orderPool.earningsFactorCurrent - order.unclaimedEarningsFactor;
                earningsAmount = (earningsFactor * order.sellRate) >> FixedPoint96.RESOLUTION;
                order.unclaimedEarningsFactor = orderPool.earningsFactorCurrent;
            }
            earningsAmount += order.uncollectedEarningsAmount;
            order.uncollectedEarningsAmount = 0;
        }
    }

    struct PoolParamsOnExecute {
        uint160 sqrtPriceX96;
        uint128 liquidity;
    }

    /// @notice Executes all existing long term orders in the TWAMM
    /// @param pool The relevant state of the pool
    function executeTWAMMOrders(
        State storage self,
        uint256 expirationInterval,
        IPoolManager poolManager,
        IPoolManager.PoolKey memory key,
        PoolParamsOnExecute memory pool
    ) internal returns (bool zeroForOne, uint160 newSqrtPriceX96) {
        if (!_hasOutstandingOrders(self)) {
            self.lastVirtualOrderTimestamp = block.timestamp;
            return (false, 0);
        }

        uint256 prevTimestamp = self.lastVirtualOrderTimestamp;
        uint256 nextExpirationTimestamp = self.lastVirtualOrderTimestamp +
            (expirationInterval - (self.lastVirtualOrderTimestamp % expirationInterval));

        return
            _executeTWAMMOrders(
                self,
                poolManager,
                key,
                pool,
                expirationInterval,
                nextExpirationTimestamp,
                prevTimestamp
            );
    }

    function _executeTWAMMOrders(
        State storage self,
        IPoolManager poolManager,
        IPoolManager.PoolKey memory key,
        PoolParamsOnExecute memory pool,
        uint256 expirationInterval,
        uint256 nextExpirationTimestamp,
        uint256 prevTimestamp
    ) private returns (bool zeroForOne, uint160 newSqrtPriceX96) {
        uint160 initialSqrtPriceX96 = pool.sqrtPriceX96;

        OrderPool.State storage orderPool0For1 = self.orderPool0For1;
        OrderPool.State storage orderPool1For0 = self.orderPool1For0;

        unchecked {
            while (nextExpirationTimestamp <= block.timestamp && _hasOutstandingOrders(self)) {
                if (
                    orderPool0For1.sellRateEndingAtInterval[nextExpirationTimestamp] > 0 ||
                    orderPool1For0.sellRateEndingAtInterval[nextExpirationTimestamp] > 0
                ) {
                    if (orderPool0For1.sellRateCurrent != 0 && orderPool1For0.sellRateCurrent != 0) {
                        pool = advanceToNewTimestamp(
                            self,
                            poolManager,
                            key,
                            AdvanceParams(
                                expirationInterval,
                                nextExpirationTimestamp,
                                (nextExpirationTimestamp - prevTimestamp) * FixedPoint96.Q96,
                                pool
                            )
                        );
                    } else {
                        pool = advanceTimestampForSinglePoolSell(
                            self,
                            poolManager,
                            key,
                            AdvanceSingleParams(
                                expirationInterval,
                                nextExpirationTimestamp,
                                nextExpirationTimestamp - prevTimestamp,
                                pool,
                                orderPool0For1.sellRateCurrent != 0
                            )
                        );
                    }
                    prevTimestamp = nextExpirationTimestamp;
                }
                nextExpirationTimestamp += expirationInterval;
            }

            if (prevTimestamp < block.timestamp && _hasOutstandingOrders(self)) {
                if (orderPool0For1.sellRateCurrent != 0 && orderPool1For0.sellRateCurrent != 0) {
                    pool = advanceToNewTimestamp(
                        self,
                        poolManager,
                        key,
                        AdvanceParams(
                            expirationInterval,
                            block.timestamp,
                            (block.timestamp - prevTimestamp) * FixedPoint96.Q96,
                            pool
                        )
                    );
                } else {
                    pool = advanceTimestampForSinglePoolSell(
                        self,
                        poolManager,
                        key,
                        AdvanceSingleParams(
                            expirationInterval,
                            block.timestamp,
                            block.timestamp - prevTimestamp,
                            pool,
                            orderPool0For1.sellRateCurrent != 0
                        )
                    );
                }
            }
        }

        self.lastVirtualOrderTimestamp = block.timestamp;
        newSqrtPriceX96 = pool.sqrtPriceX96;
        zeroForOne = initialSqrtPriceX96 > newSqrtPriceX96;
    }

    struct AdvanceParams {
        uint256 expirationInterval;
        uint256 nextTimestamp;
        uint256 secondsElapsedX96;
        PoolParamsOnExecute pool;
    }

    function advanceToNewTimestamp(
        State storage self,
        IPoolManager poolManager,
        IPoolManager.PoolKey memory poolKey,
        AdvanceParams memory params
    ) private returns (PoolParamsOnExecute memory) {
        uint160 finalSqrtPriceX96;

        OrderPool.State storage orderPool0For1 = self.orderPool0For1;
        OrderPool.State storage orderPool1For0 = self.orderPool1For0;

        while (true) {
            uint256 earningsFactorPool0;
            uint256 earningsFactorPool1;
            (finalSqrtPriceX96, earningsFactorPool0, earningsFactorPool1) = TwammMath.calculateExecutionUpdates(
                TwammMath.ExecutionUpdateParams(
                    params.secondsElapsedX96,
                    params.pool.sqrtPriceX96,
                    params.pool.liquidity,
                    orderPool0For1.sellRateCurrent,
                    orderPool1For0.sellRateCurrent
                )
            );

            (bool crossingInitializedTick, int24 tick) = getNextInitializedTick(
                params.pool,
                poolManager,
                poolKey,
                finalSqrtPriceX96
            );
            unchecked {
                if (crossingInitializedTick) {
                    uint256 secondsUntilCrossingX96;
                    (params.pool, secondsUntilCrossingX96) = advanceTimeThroughTickCrossing(
                        self,
                        poolManager,
                        poolKey,
                        TickCrossingParams(tick, params.nextTimestamp, params.secondsElapsedX96, params.pool)
                    );
                    params.secondsElapsedX96 = params.secondsElapsedX96 - secondsUntilCrossingX96;
                } else {
                    if (params.nextTimestamp % params.expirationInterval == 0) {
                        orderPool0For1.advanceToInterval(params.nextTimestamp, earningsFactorPool0);
                        orderPool1For0.advanceToInterval(params.nextTimestamp, earningsFactorPool1);
                    } else {
                        orderPool0For1.advanceToCurrentTime(earningsFactorPool0);
                        orderPool1For0.advanceToCurrentTime(earningsFactorPool1);
                    }
                    params.pool.sqrtPriceX96 = finalSqrtPriceX96;
                    break;
                }
            }
        }

        return params.pool;
    }

    struct AdvanceSingleParams {
        uint256 expirationInterval;
        uint256 nextTimestamp;
        uint256 secondsElapsed;
        PoolParamsOnExecute pool;
        bool zeroForOne;
    }

    function advanceTimestampForSinglePoolSell(
        State storage self,
        IPoolManager poolManager,
        IPoolManager.PoolKey memory poolKey,
        AdvanceSingleParams memory params
    ) private returns (PoolParamsOnExecute memory) {
        OrderPool.State storage orderPool = params.zeroForOne ? self.orderPool0For1 : self.orderPool1For0;
        uint256 sellRateCurrent = orderPool.sellRateCurrent;
        uint256 amountSelling = sellRateCurrent * params.secondsElapsed;
        uint256 totalEarnings;

        while (true) {
            uint160 finalSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                params.pool.sqrtPriceX96,
                params.pool.liquidity,
                amountSelling,
                params.zeroForOne
            );

            (bool crossingInitializedTick, int24 tick) = getNextInitializedTick(
                params.pool,
                poolManager,
                poolKey,
                finalSqrtPriceX96
            );

            if (crossingInitializedTick) {
                uint160 initializedSqrtPrice = TickMath.getSqrtRatioAtTick(tick);

                uint256 swapDelta0 = SqrtPriceMath.getAmount0Delta(
                    params.pool.sqrtPriceX96,
                    initializedSqrtPrice,
                    params.pool.liquidity,
                    true
                );
                uint256 swapDelta1 = SqrtPriceMath.getAmount1Delta(
                    params.pool.sqrtPriceX96,
                    initializedSqrtPrice,
                    params.pool.liquidity,
                    true
                );

                int128 liquidityNet = poolManager.getTickNetLiquidity(poolKey, tick);
                if (params.zeroForOne) liquidityNet = -liquidityNet;
                params.pool.liquidity = params.zeroForOne
                    ? params.pool.liquidity - uint128(-liquidityNet)
                    : params.pool.liquidity + uint128(liquidityNet);
                params.pool.sqrtPriceX96 = initializedSqrtPrice;

                unchecked {
                    totalEarnings += params.zeroForOne ? swapDelta1 : swapDelta0;
                    amountSelling -= params.zeroForOne ? swapDelta0 : swapDelta1;
                }
            } else {
                if (params.zeroForOne) {
                    totalEarnings += SqrtPriceMath.getAmount1Delta(
                        params.pool.sqrtPriceX96,
                        finalSqrtPriceX96,
                        params.pool.liquidity,
                        true
                    );
                } else {
                    totalEarnings += SqrtPriceMath.getAmount0Delta(
                        params.pool.sqrtPriceX96,
                        finalSqrtPriceX96,
                        params.pool.liquidity,
                        true
                    );
                }

                uint256 accruedEarningsFactor = (totalEarnings * FixedPoint96.Q96) / sellRateCurrent;

                if (params.nextTimestamp % params.expirationInterval == 0) {
                    orderPool.advanceToInterval(params.nextTimestamp, accruedEarningsFactor);
                } else {
                    orderPool.advanceToCurrentTime(accruedEarningsFactor);
                }
                params.pool.sqrtPriceX96 = finalSqrtPriceX96;
                break;
            }
        }

        return params.pool;
    }

    struct TickCrossingParams {
        int24 initializedTick;
        uint256 nextTimestamp;
        uint256 secondsElapsedX96;
        PoolParamsOnExecute pool;
    }

    function advanceTimeThroughTickCrossing(
        State storage self,
        IPoolManager poolManager,
        IPoolManager.PoolKey memory poolKey,
        TickCrossingParams memory params
    ) private returns (PoolParamsOnExecute memory, uint256) {
        uint160 initializedSqrtPrice = params.initializedTick.getSqrtRatioAtTick();

        OrderPool.State storage orderPool0For1 = self.orderPool0For1;
        OrderPool.State storage orderPool1For0 = self.orderPool1For0;

        uint256 secondsUntilCrossingX96 = TwammMath.calculateTimeBetweenTicks(
            params.pool.liquidity,
            params.pool.sqrtPriceX96,
            initializedSqrtPrice,
            orderPool0For1.sellRateCurrent,
            orderPool1For0.sellRateCurrent
        );

        // TODO: nextSqrtPriceX96 off by 1 wei (hence using the initializedSqrtPrice (l:331) param instead)
        (uint160 nextSqrtPriceX96, uint256 earningsFactorPool0, uint256 earningsFactorPool1) = TwammMath
            .calculateExecutionUpdates(
                TwammMath.ExecutionUpdateParams(
                    secondsUntilCrossingX96,
                    params.pool.sqrtPriceX96,
                    params.pool.liquidity,
                    orderPool0For1.sellRateCurrent,
                    orderPool1For0.sellRateCurrent
                )
            );
        orderPool0For1.advanceToCurrentTime(earningsFactorPool0);
        orderPool1For0.advanceToCurrentTime(earningsFactorPool1);

        unchecked {
            // update pool
            int128 liquidityNet = poolManager.getTickNetLiquidity(poolKey, params.initializedTick);
            if (initializedSqrtPrice < params.pool.sqrtPriceX96) liquidityNet = -liquidityNet;
            params.pool.liquidity = liquidityNet < 0
                ? params.pool.liquidity - uint128(-liquidityNet)
                : params.pool.liquidity + uint128(liquidityNet);
            params.pool.sqrtPriceX96 = initializedSqrtPrice;
        }
        return (params.pool, secondsUntilCrossingX96);
    }

    function getNextInitializedTick(
        PoolParamsOnExecute memory pool,
        IPoolManager poolManager,
        IPoolManager.PoolKey memory poolKey,
        uint160 nextSqrtPriceX96
    ) private view returns (bool initialized, int24 nextTickInit) {
        // use current price as a starting point for nextTickInit
        nextTickInit = pool.sqrtPriceX96.getTickAtSqrtRatio();
        bool searchingLeft = nextSqrtPriceX96 < pool.sqrtPriceX96;
        int24 targetTick = nextSqrtPriceX96.getTickAtSqrtRatio();

        while (!searchingLeft ? nextTickInit < targetTick : nextTickInit > targetTick) {
            unchecked {
                if (searchingLeft) nextTickInit -= 1;
            }
            (nextTickInit, initialized) = poolManager.nextInitializedTickWithinOneWord(
                poolKey,
                nextTickInit,
                searchingLeft
            );
            if (initialized == true) break;
        }
    }

    function _getOrder(State storage self, OrderKey memory key) internal view returns (Order storage) {
        return self.orders[_orderId(key)];
    }

    function _orderId(OrderKey memory key) private pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    function _hasOutstandingOrders(State storage self) internal view returns (bool) {
        return !(self.orderPool0For1.sellRateCurrent == 0 && self.orderPool1For0.sellRateCurrent == 0);
    }
}
