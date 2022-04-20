// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Tick} from '../Tick.sol';
import {TickBitmap} from '../TickBitmap.sol';
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
    /// @member expirationInterval Interval in seconds between valid order expiration timestamps
    /// @member lastVirtualOrderTimestamp Last timestamp in which virtual orders were executed
    /// @member orderPools Mapping from token index (0 and 1) to OrderPool that is selling that token
    /// @member orders Mapping of orderId to individual orders
    /// @member nextId Id for next submitted order
    struct State {
        uint256 expirationInterval;
        uint256 lastVirtualOrderTimestamp;
        mapping(uint8 => OrderPool.State) orderPools;
        mapping(bytes32 => Order) orders;
    }

    /// @notice Information that identifies an order
    /// @member owner Owner of the order
    /// @member expiration Timestamp when the order expires
    /// @member zeroForOne Index of sell token, 0 for token0, 1 for token1
    struct OrderKey {
        address owner;
        uint256 expiration;
        bool zeroForOne;
    }

    /// @notice Information associated with a long term order
    /// @member sellTokenIndex Index of sell token, 0 for token0, 1 for token1
    /// @member owner Owner of the order
    /// @member expiration Timestamp when the order expires
    /// @member sellRate Amount of tokens sold per interval
    /// @member unclaimedEarningsFactor The accrued earnings factor from which to start claiming owed earnings for this order
    /// @member uncollectedEarningsAmount Earnings amount claimed thus far, but not yet transferred to the owner.
    struct Order {
        uint8 sellTokenIndex;
        uint256 expiration;
        uint256 sellRate;
        uint256 unclaimedEarningsFactor;
        uint256 uncollectedEarningsAmount;
    }

    /// @notice Initialize TWAMM state
    /// @param expirationInterval Time interval on which orders can expire
    function initialize(State storage self, uint256 expirationInterval) internal {
        // TODO: could enforce a 1 time call...but redundant in the context of Pool
        self.expirationInterval = expirationInterval;
        self.lastVirtualOrderTimestamp = block.timestamp;
    }

    struct LongTermOrderParams {
        bool zeroForOne;
        address owner;
        uint256 amountIn;
        uint256 expiration;
    }

    /// @notice Submits a new long term order into the TWAMM
    /// @param params All parameters to define the new order
    function submitLongTermOrder(State storage self, LongTermOrderParams memory params)
        internal
        returns (bytes32 orderId)
    {
        if (self.expirationInterval == 0) revert NotInitialized();
        if (params.expiration < block.timestamp) revert ExpirationLessThanBlocktime(params.expiration);
        if (params.expiration % self.expirationInterval != 0) revert ExpirationNotOnInterval(params.expiration);

        orderId = _orderId(OrderKey(params.owner, params.expiration, params.zeroForOne));
        if (self.orders[orderId].sellRate != 0) revert OrderAlreadyExists(orderId);

        uint8 sellTokenIndex = params.zeroForOne ? 0 : 1;
        uint256 sellRate;

        unchecked {
            sellRate = params.amountIn / (params.expiration - block.timestamp);
            self.orderPools[sellTokenIndex].sellRateCurrent += sellRate;
            self.orderPools[sellTokenIndex].sellRateEndingAtInterval[params.expiration] += sellRate;
        }

        self.orders[orderId] = Order({
            expiration: params.expiration,
            sellRate: sellRate,
            sellTokenIndex: sellTokenIndex,
            unclaimedEarningsFactor: self.orderPools[sellTokenIndex].earningsFactorCurrent,
            uncollectedEarningsAmount: 0
        });
    }

    /// @notice Modify an existing long term order with a new sellAmount
    /// @param self The TWAMM State
    /// @param orderKey The OrderKey for which to identify the order
    /// @param amountDelta The delta for the order sell amount. Negative to remove from order, positive to add, or
    ///    min value to remove full amount from order.
    function modifyLongTermOrder(
        State storage self,
        OrderKey memory orderKey,
        int128 amountDelta
    ) internal returns (uint256 amountOut0, uint256 amountOut1) {
        bytes32 orderId = _orderId(orderKey);
        Order storage order = _getOrder(self, orderKey);
        if (orderKey.owner == address(0)) revert OrderDoesNotExist(orderId);
        if (orderKey.owner != msg.sender) revert MustBeOwner(orderId, orderKey.owner, msg.sender);
        if (order.expiration <= block.timestamp) revert OrderAlreadyCompleted(orderId);

        unchecked {
            // cache existing earnings
            uint256 earningsFactor = self.orderPools[order.sellTokenIndex].earningsFactorCurrent -
                order.unclaimedEarningsFactor;
            order.uncollectedEarningsAmount += (earningsFactor * order.sellRate) >> FixedPoint96.RESOLUTION;
            order.unclaimedEarningsFactor = self.orderPools[order.sellTokenIndex].earningsFactorCurrent;

            uint256 unsoldAmount = order.sellRate * (order.expiration - block.timestamp);
            if (amountDelta == type(int128).min) amountDelta = -unsoldAmount.toInt256().toInt128();
            uint256 newSellAmount = uint256(int256(unsoldAmount) + amountDelta);
            if (newSellAmount < 0) revert InvalidAmountDelta(orderId, unsoldAmount, amountDelta);

            uint256 newSellRate = newSellAmount / (order.expiration - block.timestamp);

            if (amountDelta < 0) {
                uint256 sellRateDelta = order.sellRate - newSellRate;
                uint256 amountOut = uint256(uint128(-amountDelta));
                self.orderPools[order.sellTokenIndex].sellRateCurrent -= sellRateDelta;
                self.orderPools[order.sellTokenIndex].sellRateEndingAtInterval[order.expiration] -= sellRateDelta;
                orderKey.zeroForOne ? amountOut0 = amountOut : amountOut1 = amountOut;
            } else {
                uint256 sellRateDelta = newSellRate - order.sellRate;
                self.orderPools[order.sellTokenIndex].sellRateCurrent += sellRateDelta;
                self.orderPools[order.sellTokenIndex].sellRateEndingAtInterval[order.expiration] += sellRateDelta;
            }
            order.sellRate = newSellRate;
        }
    }

    /// @notice Claim earnings from an ongoing or expired order
    /// @param orderKey The key of the order to be claimed
    function claimEarnings(State storage self, OrderKey memory orderKey)
        internal
        returns (uint256 earningsAmount, uint8 sellTokenIndex)
    {
        bytes32 orderId = _orderId(orderKey);
        Order memory order = self.orders[orderId];
        sellTokenIndex = order.sellTokenIndex;
        OrderPool.State storage orderPool = self.orderPools[sellTokenIndex];

        unchecked {
            if (block.timestamp > order.expiration) {
                uint256 earningsFactor = orderPool.earningsFactorAtInterval[order.expiration] -
                    order.unclaimedEarningsFactor;
                earningsAmount = (earningsFactor * order.sellRate) >> FixedPoint96.RESOLUTION;
                self.orders[orderId].sellRate = 0;
            } else {
                uint256 earningsFactor = orderPool.earningsFactorCurrent - order.unclaimedEarningsFactor;
                earningsAmount = (earningsFactor * order.sellRate) >> FixedPoint96.RESOLUTION;
                self.orders[orderId].unclaimedEarningsFactor = orderPool.earningsFactorCurrent;
            }
        }
    }

    struct PoolParamsOnExecute {
        uint160 sqrtPriceX96;
        uint128 liquidity;
        uint24 fee;
        int24 tickSpacing;
    }

    struct OrderPoolParamsOnExecute {
        uint256 sellRateCurrent0;
        uint256 sellRateCurrent1;
    }

    /// @notice Executes all existing long term orders in the TWAMM
    /// @param pool The relevant state of the pool
    /// @param ticks Points to tick information on the pool
    function executeTWAMMOrders(
        State storage self,
        PoolParamsOnExecute memory pool,
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint256) storage tickBitmap
    ) internal returns (bool zeroForOne, uint160 newSqrtPriceX96) {
        if (!_hasOutstandingOrders(self)) {
            self.lastVirtualOrderTimestamp = block.timestamp;
            return (false, 0);
        }

        uint256 prevTimestamp = self.lastVirtualOrderTimestamp;
        uint256 nextExpirationTimestamp = self.lastVirtualOrderTimestamp +
            (self.expirationInterval - (self.lastVirtualOrderTimestamp % self.expirationInterval));

        return _executeTWAMMOrders(self, pool, nextExpirationTimestamp, prevTimestamp, ticks, tickBitmap);
    }

    function _executeTWAMMOrders(
        State storage self,
        PoolParamsOnExecute memory pool,
        uint256 nextExpirationTimestamp,
        uint256 prevTimestamp,
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint256) storage tickBitmap
    ) private returns (bool zeroForOne, uint160 newSqrtPriceX96) {
        uint160 initialSqrtPriceX96 = pool.sqrtPriceX96;
        unchecked {
            while (nextExpirationTimestamp <= block.timestamp && _hasOutstandingOrders(self)) {
                if (
                    self.orderPools[0].sellRateEndingAtInterval[nextExpirationTimestamp] > 0 ||
                    self.orderPools[1].sellRateEndingAtInterval[nextExpirationTimestamp] > 0
                ) {
                    pool = advanceToNewTimestamp(
                        self,
                        AdvanceParams(
                            nextExpirationTimestamp,
                            (nextExpirationTimestamp - prevTimestamp) * FixedPoint96.Q96,
                            pool
                        ),
                        ticks,
                        tickBitmap
                    );
                    prevTimestamp = nextExpirationTimestamp;
                }
                nextExpirationTimestamp += self.expirationInterval;
            }

            if (prevTimestamp < block.timestamp && _hasOutstandingOrders(self)) {
                pool = advanceToNewTimestamp(
                    self,
                    AdvanceParams(block.timestamp, (block.timestamp - prevTimestamp) * FixedPoint96.Q96, pool),
                    ticks,
                    tickBitmap
                );
            }
        }

        self.lastVirtualOrderTimestamp = block.timestamp;
        newSqrtPriceX96 = pool.sqrtPriceX96;
        zeroForOne = initialSqrtPriceX96 > newSqrtPriceX96;
    }

    struct AdvanceParams {
        uint256 nextTimestamp;
        uint256 secondsElapsedX96;
        PoolParamsOnExecute pool;
    }

    function advanceToNewTimestamp(
        State storage self,
        AdvanceParams memory params,
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint256) storage tickBitmap
    ) private returns (PoolParamsOnExecute memory) {
        uint160 finalSqrtPriceX96;

        while (params.pool.sqrtPriceX96 != finalSqrtPriceX96) {
            uint256 earningsFactorPool0;
            uint256 earningsFactorPool1;
            (finalSqrtPriceX96, earningsFactorPool0, earningsFactorPool1) = TwammMath.calculateExecutionUpdates(
                params.secondsElapsedX96,
                params.pool,
                OrderPoolParamsOnExecute(self.orderPools[0].sellRateCurrent, self.orderPools[1].sellRateCurrent)
            );

            (bool crossingInitializedTick, int24 tick) = getNextInitializedTick(
                params.pool,
                finalSqrtPriceX96,
                tickBitmap
            );
            unchecked {
                if (crossingInitializedTick) {
                    uint256 secondsUntilCrossingX96;
                    (params.pool, secondsUntilCrossingX96) = advanceTimeThroughTickCrossing(
                        self,
                        TickCrossingParams(tick, params.nextTimestamp, params.secondsElapsedX96, params.pool),
                        ticks
                    );
                    params.secondsElapsedX96 = params.secondsElapsedX96 - secondsUntilCrossingX96;
                } else {
                    if (params.nextTimestamp % self.expirationInterval == 0) {
                        self.orderPools[0].advanceToInterval(params.nextTimestamp, earningsFactorPool0);
                        self.orderPools[1].advanceToInterval(params.nextTimestamp, earningsFactorPool1);
                    } else {
                        self.orderPools[0].advanceToCurrentTime(earningsFactorPool0);
                        self.orderPools[1].advanceToCurrentTime(earningsFactorPool1);
                    }
                    params.pool.sqrtPriceX96 = finalSqrtPriceX96;
                }
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
        TickCrossingParams memory params,
        mapping(int24 => Tick.Info) storage ticks
    ) private returns (PoolParamsOnExecute memory, uint256) {
        uint160 initializedSqrtPrice = params.initializedTick.getSqrtRatioAtTick();
        uint256 secondsUntilCrossingX96 = TwammMath.calculateTimeBetweenTicks(
            params.pool.liquidity,
            params.pool.sqrtPriceX96,
            initializedSqrtPrice,
            self.orderPools[0].sellRateCurrent,
            self.orderPools[1].sellRateCurrent
        );

        // TODO: nextSqrtPriceX96 off by 1 wei (hence using the initializedSqrtPrice (l:331) param instead)
        (uint160 nextSqrtPriceX96, uint256 earningsFactorPool0, uint256 earningsFactorPool1) = TwammMath
            .calculateExecutionUpdates(
                secondsUntilCrossingX96,
                params.pool,
                OrderPoolParamsOnExecute(self.orderPools[0].sellRateCurrent, self.orderPools[1].sellRateCurrent)
            );
        self.orderPools[0].advanceToCurrentTime(earningsFactorPool0);
        self.orderPools[1].advanceToCurrentTime(earningsFactorPool1);

        unchecked {
            // update pool
            int128 liquidityNet = ticks[params.initializedTick].liquidityNet;
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
        uint160 nextSqrtPriceX96,
        mapping(int16 => uint256) storage tickBitmap
    ) private returns (bool initialized, int24 nextTickInit) {
        // use current price as a starting point for nextTickInit
        nextTickInit = pool.sqrtPriceX96.getTickAtSqrtRatio();
        bool searchingLeft = nextSqrtPriceX96 < pool.sqrtPriceX96;
        int24 targetTick = nextSqrtPriceX96.getTickAtSqrtRatio();

        while (!searchingLeft ? nextTickInit < targetTick : nextTickInit > targetTick) {
            unchecked {
                if (searchingLeft) nextTickInit -= 1;
            }
            (nextTickInit, initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                nextTickInit,
                pool.tickSpacing,
                searchingLeft
            );
            if (initialized == true) break;
        }
    }

    function _getOrder(State storage self, OrderKey memory key) internal view returns (Order storage) {
        return self.orders[keccak256(abi.encode(key))];
    }

    function _orderId(OrderKey memory key) private view returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    function _hasOutstandingOrders(State storage self) internal view returns (bool) {
        return !(self.orderPools[0].sellRateCurrent == 0 && self.orderPools[1].sellRateCurrent == 0);
    }
}
