// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Tick} from '../Tick.sol';
import {TickBitmap} from '../TickBitmap.sol';
import {IPoolManager} from '../../interfaces/IPoolManager.sol';
import {PoolId} from '../PoolId.sol';
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
    using PoolId for IPoolManager.PoolKey;
    using TickMath for int24;
    using TickMath for uint160;
    using SafeCast for uint256;
    using TickBitmap for mapping(int16 => uint256);

    int256 internal constant MIN_DELTA = -1;
    bool internal constant ZERO_FOR_ONE = true;
    bool internal constant ONE_FOR_ZERO = false;

    /// @notice Thrown when account other than owner attempts to interact with an order
    /// @param owner The owner of the order
    /// @param currentAccount The invalid account attempting to interact with the order
    error MustBeOwner(address owner, address currentAccount);

    /// @notice Thrown when trying to cancel an already completed order
    /// @param orderKey The orderKey
    error CannotModifyCompletedOrder(OrderKey orderKey);

    /// @notice Thrown when trying to submit an order with an expiration that isn't on the interval.
    /// @param expiration The expiration timestamp of the order
    error ExpirationNotOnInterval(uint256 expiration);

    /// @notice Thrown when trying to submit an order with an expiration time in the past.
    /// @param expiration The expiration timestamp of the order
    error ExpirationLessThanBlocktime(uint256 expiration);

    /// @notice Thrown when trying to submit an order without initializing TWAMM state first
    error NotInitialized();

    /// @notice Thrown when trying to submit an order that's already ongoing.
    /// @param orderKey The already existing orderKey
    error OrderAlreadyExists(OrderKey orderKey);

    /// @notice Thrown when trying to interact with an order that does not exist.
    /// @param orderKey The already existing orderKey
    error OrderDoesNotExist(OrderKey orderKey);

    /// @notice Thrown when trying to subtract more value from a long term order than exists
    /// @param orderKey The orderKey
    /// @param unsoldAmount The amount still unsold
    /// @param amountDelta The amount delta for the order
    error InvalidAmountDelta(OrderKey orderKey, uint256 unsoldAmount, int256 amountDelta);

    /// @notice Thrown when submitting an order with a sellRate of 0
    error SellRateCannotBeZero();

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
    /// @member sellRate Amount of tokens sold per interval
    /// @member earningsFactorLast The accrued earnings factor from which to start claiming owed earnings for this order
    struct Order {
        uint256 sellRate;
        uint256 earningsFactorLast;
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
    /// @dev executeTWAMMOrders must be executed up to current timestamp before calling submitLongTermOrder
    /// @param orderKey The OrderKey for the new order
    function submitLongTermOrder(
        State storage self,
        OrderKey memory orderKey,
        uint256 sellRate,
        uint256 expirationInterval
    ) internal returns (bytes32 orderId) {
        if (orderKey.owner != msg.sender) revert MustBeOwner(orderKey.owner, msg.sender);
        if (self.lastVirtualOrderTimestamp == 0) revert NotInitialized();
        if (orderKey.expiration <= block.timestamp) revert ExpirationLessThanBlocktime(orderKey.expiration);
        if (sellRate == 0) revert SellRateCannotBeZero();
        if (orderKey.expiration % expirationInterval != 0) revert ExpirationNotOnInterval(orderKey.expiration);

        orderId = _orderId(orderKey);
        if (self.orders[orderId].sellRate != 0) revert OrderAlreadyExists(orderKey);

        OrderPool.State storage orderPool = orderKey.zeroForOne ? self.orderPool0For1 : self.orderPool1For0;

        unchecked {
            orderPool.sellRateCurrent += sellRate;
            orderPool.sellRateEndingAtInterval[orderKey.expiration] += sellRate;
        }

        self.orders[orderId] = Order({sellRate: sellRate, earningsFactorLast: orderPool.earningsFactorCurrent});
    }

    /// @notice Modify an existing long term order with a new sellAmount
    /// @dev executeTWAMMOrders must be executed up to current timestamp before calling updateLongTermOrder
    /// @param self The TWAMM State
    /// @param orderKey The OrderKey for which to identify the order
    /// @param amountDelta The delta for the order sell amount. Negative to remove from order, positive to add, or
    ///    -1 to remove full amount from order.
    function updateLongTermOrder(
        State storage self,
        OrderKey memory orderKey,
        int256 amountDelta
    )
        internal
        returns (
            uint256 buyTokensOwed,
            uint256 sellTokensOwed,
            uint256 newSellRate,
            uint256 earningsFactorLast
        )
    {
        Order storage order = getOrder(self, orderKey);

        if (orderKey.owner != msg.sender) revert MustBeOwner(orderKey.owner, msg.sender);
        if (order.sellRate == 0) revert OrderDoesNotExist(orderKey);
        if (amountDelta != 0 && orderKey.expiration <= block.timestamp) revert CannotModifyCompletedOrder(orderKey);

        OrderPool.State storage orderPool = orderKey.zeroForOne ? self.orderPool0For1 : self.orderPool1For0;

        unchecked {
            uint256 earningsFactor = orderPool.earningsFactorCurrent - order.earningsFactorLast;
            buyTokensOwed = (earningsFactor * order.sellRate) >> FixedPoint96.RESOLUTION;
            earningsFactorLast = orderPool.earningsFactorCurrent;
            order.earningsFactorLast = earningsFactorLast;

            if (orderKey.expiration <= block.timestamp) {
                delete self.orders[_orderId(orderKey)];
            }

            if (amountDelta != 0) {
                uint256 duration = orderKey.expiration - block.timestamp;
                uint256 unsoldAmount = order.sellRate * duration;
                if (amountDelta == MIN_DELTA) amountDelta = -(unsoldAmount.toInt256());
                int256 newSellAmount = unsoldAmount.toInt256() + amountDelta;
                if (newSellAmount < 0) revert InvalidAmountDelta(orderKey, unsoldAmount, amountDelta);

                newSellRate = uint256(newSellAmount) / duration;

                if (amountDelta < 0) {
                    uint256 sellRateDelta = order.sellRate - newSellRate;
                    orderPool.sellRateCurrent -= sellRateDelta;
                    orderPool.sellRateEndingAtInterval[orderKey.expiration] -= sellRateDelta;
                    sellTokensOwed = uint256(-amountDelta);
                } else {
                    uint256 sellRateDelta = newSellRate - order.sellRate;
                    orderPool.sellRateCurrent += sellRateDelta;
                    orderPool.sellRateEndingAtInterval[orderKey.expiration] += sellRateDelta;
                }
                if (newSellRate == 0) {
                    delete self.orders[_orderId(orderKey)];
                } else {
                    order.sellRate = newSellRate;
                }
            }
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
        IPoolManager poolManager,
        IPoolManager.PoolKey memory key,
        PoolParamsOnExecute memory pool,
        uint256 expirationInterval
    ) internal returns (bool zeroForOne, uint160 newSqrtPriceX96) {
        if (!_hasOutstandingOrders(self)) {
            self.lastVirtualOrderTimestamp = block.timestamp;
            return (false, 0);
        }

        uint160 initialSqrtPriceX96 = pool.sqrtPriceX96;
        uint256 prevTimestamp = self.lastVirtualOrderTimestamp;
        uint256 nextExpirationTimestamp = prevTimestamp + (expirationInterval - (prevTimestamp % expirationInterval));

        OrderPool.State storage orderPool0For1 = self.orderPool0For1;
        OrderPool.State storage orderPool1For0 = self.orderPool1For0;

        unchecked {
            while (nextExpirationTimestamp <= block.timestamp) {
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
                                nextExpirationTimestamp - prevTimestamp,
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

                if (!_hasOutstandingOrders(self)) break;
            }

            if (prevTimestamp < block.timestamp && _hasOutstandingOrders(self)) {
                if (orderPool0For1.sellRateCurrent != 0 && orderPool1For0.sellRateCurrent != 0) {
                    pool = advanceToNewTimestamp(
                        self,
                        poolManager,
                        key,
                        AdvanceParams(expirationInterval, block.timestamp, block.timestamp - prevTimestamp, pool)
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
        uint256 secondsElapsed;
        PoolParamsOnExecute pool;
    }

    function advanceToNewTimestamp(
        State storage self,
        IPoolManager poolManager,
        IPoolManager.PoolKey memory poolKey,
        AdvanceParams memory params
    ) private returns (PoolParamsOnExecute memory) {
        uint160 finalSqrtPriceX96;
        uint256 secondsElapsedX96 = params.secondsElapsed * FixedPoint96.Q96;

        OrderPool.State storage orderPool0For1 = self.orderPool0For1;
        OrderPool.State storage orderPool1For0 = self.orderPool1For0;

        while (true) {
            TwammMath.ExecutionUpdateParams memory executionParams = TwammMath.ExecutionUpdateParams(
                secondsElapsedX96,
                params.pool.sqrtPriceX96,
                params.pool.liquidity,
                orderPool0For1.sellRateCurrent,
                orderPool1For0.sellRateCurrent
            );

            finalSqrtPriceX96 = TwammMath.getNewSqrtPriceX96(executionParams);

            (bool crossingInitializedTick, int24 tick) = isCrossingInitializedTick(
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
                        TickCrossingParams(tick, params.nextTimestamp, secondsElapsedX96, params.pool)
                    );
                    secondsElapsedX96 = secondsElapsedX96 - secondsUntilCrossingX96;
                } else {
                    (uint256 earningsFactorPool0, uint256 earningsFactorPool1) = TwammMath.calculateEarningsUpdates(
                        executionParams,
                        finalSqrtPriceX96
                    );

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

            (bool crossingInitializedTick, int24 tick) = isCrossingInitializedTick(
                params.pool,
                poolManager,
                poolKey,
                finalSqrtPriceX96
            );

            if (crossingInitializedTick) {
                int128 liquidityNetAtTick = poolManager.getTickNetLiquidity(poolKey.toId(), tick);
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

                params.pool.liquidity = params.zeroForOne
                    ? params.pool.liquidity - uint128(liquidityNetAtTick)
                    : params.pool.liquidity + uint128(-liquidityNetAtTick);
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

        uint256 secondsUntilCrossingX96 = TwammMath.calculateTimeBetweenTicks(
            params.pool.liquidity,
            params.pool.sqrtPriceX96,
            initializedSqrtPrice,
            self.orderPool0For1.sellRateCurrent,
            self.orderPool1For0.sellRateCurrent
        );

        (uint256 earningsFactorPool0, uint256 earningsFactorPool1) = TwammMath.calculateEarningsUpdates(
            TwammMath.ExecutionUpdateParams(
                secondsUntilCrossingX96,
                params.pool.sqrtPriceX96,
                params.pool.liquidity,
                self.orderPool0For1.sellRateCurrent,
                self.orderPool1For0.sellRateCurrent
            ),
            initializedSqrtPrice
        );

        self.orderPool0For1.advanceToCurrentTime(earningsFactorPool0);
        self.orderPool1For0.advanceToCurrentTime(earningsFactorPool1);

        unchecked {
            // update pool
            int128 liquidityNet = poolManager.getTickNetLiquidity(poolKey.toId(), params.initializedTick);
            if (initializedSqrtPrice < params.pool.sqrtPriceX96) liquidityNet = -liquidityNet;
            params.pool.liquidity = liquidityNet < 0
                ? params.pool.liquidity - uint128(-liquidityNet)
                : params.pool.liquidity + uint128(liquidityNet);

            params.pool.sqrtPriceX96 = initializedSqrtPrice;
        }
        return (params.pool, secondsUntilCrossingX96);
    }

    function isCrossingInitializedTick(
        PoolParamsOnExecute memory pool,
        IPoolManager poolManager,
        IPoolManager.PoolKey memory poolKey,
        uint160 nextSqrtPriceX96
    ) internal view returns (bool crossingInitializedTick, int24 nextTickInit) {
        // use current price as a starting point for nextTickInit
        nextTickInit = pool.sqrtPriceX96.getTickAtSqrtRatio();
        int24 targetTick = nextSqrtPriceX96.getTickAtSqrtRatio();
        bool searchingLeft = nextSqrtPriceX96 < pool.sqrtPriceX96;
        bool nextTickInitFurtherThanTarget = false; // initialize as false

        // nextTickInit returns the furthest tick within one word if no tick within that word is initialized
        // so we must keep iterating if we haven't reached a tick further than our target tick
        while (!nextTickInitFurtherThanTarget) {
            unchecked {
                if (searchingLeft) nextTickInit -= 1;
            }
            (nextTickInit, crossingInitializedTick) = poolManager.getNextInitializedTickWithinOneWord(
                poolKey,
                nextTickInit,
                searchingLeft
            );
            nextTickInitFurtherThanTarget = searchingLeft ? nextTickInit <= targetTick : nextTickInit > targetTick;
            if (crossingInitializedTick == true) break;
        }
        if (nextTickInitFurtherThanTarget) crossingInitializedTick = false;
    }

    function getOrder(State storage self, OrderKey memory key) internal view returns (Order storage) {
        return self.orders[_orderId(key)];
    }

    function _orderId(OrderKey memory key) private pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    function _hasOutstandingOrders(State storage self) internal view returns (bool) {
        return self.orderPool0For1.sellRateCurrent != 0 || self.orderPool1For0.sellRateCurrent != 0;
    }
}
