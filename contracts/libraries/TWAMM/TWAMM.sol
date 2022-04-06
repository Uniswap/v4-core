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

/// @title TWAMM - Time Weighted Average Market Maker
/// @notice TWAMM represents long term orders in a pool
library TWAMM {
    using OrderPool for OrderPool.State;
    using TickMath for *;
    using TickBitmap for mapping(int16 => uint256);

    /// @notice Thrown when account other than owner attempts to interact with an order
    /// @param orderId The orderId
    /// @param owner The owner of the order
    /// @param currentAccount The invalid account attempting to interact with the order
    error MustBeOwner(bytes32 orderId, address owner, address currentAccount);

    /// @notice Thrown when trying to cancel an already completed order
    /// @param orderId The orderId
    /// @param expiration The expiration timestamp of the order
    /// @param currentTime The current block timestamp
    error OrderAlreadyCompleted(bytes32 orderId, uint256 expiration, uint256 currentTime);

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
    struct Order {
        uint8 sellTokenIndex;
        uint256 expiration;
        uint256 sellRate;
        uint256 unclaimedEarningsFactor;
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
    function submitLongTermOrder(State storage self, LongTermOrderParams calldata params)
        internal
        returns (bytes32 orderId)
    {
        if (self.expirationInterval == 0) revert NotInitialized();
        if (params.expiration < block.timestamp) revert ExpirationLessThanBlocktime(params.expiration);
        if (params.expiration % self.expirationInterval != 0) revert ExpirationNotOnInterval(params.expiration);

        orderId = _orderId(OrderKey(params.owner, params.expiration, params.zeroForOne));
        if (self.orders[orderId].sellRate != 0) revert OrderAlreadyExists(orderId);

        uint8 sellTokenIndex = params.zeroForOne ? 0 : 1;
        uint256 sellRate = params.amountIn / (params.expiration - block.timestamp);

        self.orderPools[sellTokenIndex].sellRateCurrent += sellRate;
        self.orderPools[sellTokenIndex].sellRateEndingAtInterval[params.expiration] += sellRate;

        self.orders[orderId] = Order({
            expiration: params.expiration,
            sellRate: sellRate,
            sellTokenIndex: sellTokenIndex,
            unclaimedEarningsFactor: self.orderPools[sellTokenIndex].earningsFactorCurrent
        });
    }

    /// @notice Cancels a long term order and updates procceeds owed in both tokens
    ///   back to the owner
    /// @param orderKey The key of the order to be cancelled
    function cancelLongTermOrder(State storage self, OrderKey calldata orderKey)
        internal
        returns (uint256 amountOut0, uint256 amountOut1)
    {
        bytes32 orderId = _orderId(orderKey);
        Order storage order = _getOrder(self, orderKey);
        if (orderKey.owner != msg.sender) revert MustBeOwner(orderId, orderKey.owner, msg.sender);
        if (order.expiration <= block.timestamp)
            revert OrderAlreadyCompleted(orderId, order.expiration, block.timestamp);

        uint256 earningsFactorCurrent = self.orderPools[order.sellTokenIndex].earningsFactorCurrent;
        (amountOut0, amountOut1) = TwammMath.calculateCancellationAmounts(
            order,
            earningsFactorCurrent,
            block.timestamp
        );
        if (order.sellTokenIndex == 1) (amountOut1, amountOut0) = (amountOut0, amountOut1);

        self.orderPools[order.sellTokenIndex].sellRateCurrent -= order.sellRate;
        self.orderPools[order.sellTokenIndex].sellRateEndingAtInterval[order.expiration] -= order.sellRate;
        order.sellRate = 0;
    }

    /// @notice Claim earnings from an ongoing or expired order
    /// @param orderKey The key of the order to be claimed
    function claimEarnings(State storage self, OrderKey calldata orderKey)
        internal
        returns (uint256 earningsAmount, uint8 sellTokenIndex)
    {
        bytes32 orderId = _orderId(orderKey);
        Order memory order = self.orders[orderId];
        sellTokenIndex = order.sellTokenIndex;
        OrderPool.State storage orderPool = self.orderPools[sellTokenIndex];

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
        if (self.orderPools[0].sellRateCurrent == 0 && self.orderPools[1].sellRateCurrent == 0) {
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
        while (nextExpirationTimestamp <= block.timestamp) {
            if (
                self.orderPools[0].sellRateEndingAtInterval[nextExpirationTimestamp] > 0 ||
                self.orderPools[1].sellRateEndingAtInterval[nextExpirationTimestamp] > 0
            ) {
                pool = advanceToNewTimestamp(
                    self,
                    AdvanceParams(nextExpirationTimestamp, nextExpirationTimestamp - prevTimestamp, pool, false),
                    ticks,
                    tickBitmap
                );
                prevTimestamp = nextExpirationTimestamp;
            }
            nextExpirationTimestamp += self.expirationInterval;
        }

        if (prevTimestamp < block.timestamp) {
            pool = advanceToNewTimestamp(
                self,
                AdvanceParams(block.timestamp, block.timestamp - prevTimestamp, pool, false),
                ticks,
                tickBitmap
            );
        }

        self.lastVirtualOrderTimestamp = block.timestamp;
        newSqrtPriceX96 = pool.sqrtPriceX96;
        zeroForOne = initialSqrtPriceX96 > newSqrtPriceX96;
    }

    struct AdvanceParams {
        uint256 nextTimestamp;
        uint256 secondsElapsed;
        PoolParamsOnExecute pool;
        bool isCurrentlyCrossing;
    }

    function advanceToNewTimestamp(
        State storage self,
        AdvanceParams memory params,
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint256) storage tickBitmap
    ) private returns (PoolParamsOnExecute memory updatedPool) {
        (uint160 nextSqrtPriceX96, uint256 earningsPool0, uint256 earningsPool1) = TwammMath.calculateExecutionUpdates(
            params.secondsElapsed,
            params.pool,
            OrderPoolParamsOnExecute(self.orderPools[0].sellRateCurrent, self.orderPools[1].sellRateCurrent),
            ticks
        );

        bool crossingInitializedTick;
        int24 tick;
        if (!params.isCurrentlyCrossing) {
            (crossingInitializedTick, tick) = getNextInitializedTick(params.pool, nextSqrtPriceX96, tickBitmap);
        }
        if (crossingInitializedTick) {
            return
                advanceTimeToTickCrossing(
                    self,
                    TickCrossingParams(tick, params.nextTimestamp, params.secondsElapsed, params.pool),
                    ticks,
                    tickBitmap
                );
        } else {
            if (params.nextTimestamp % self.expirationInterval == 0) {
                self.orderPools[0].advanceToInterval(params.nextTimestamp, earningsPool0);
                self.orderPools[1].advanceToInterval(params.nextTimestamp, earningsPool1);
            } else {
                self.orderPools[0].advanceToCurrentTime(earningsPool0);
                self.orderPools[1].advanceToCurrentTime(earningsPool1);
            }

            params.pool.sqrtPriceX96 = nextSqrtPriceX96;
            updatedPool = params.pool;
        }
    }

    struct TickCrossingParams {
        int24 initializedTick;
        uint256 nextTimestamp;
        uint256 secondsElapsed;
        PoolParamsOnExecute pool;
    }

    function advanceTimeToTickCrossing(
        State storage self,
        TickCrossingParams memory params,
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint256) storage tickBitmap
    ) private returns (PoolParamsOnExecute memory updatedPool) {
        uint256 secondsUntilCrossing = TwammMath.calculateTimeBetweenTicks(
            params.pool.liquidity,
            params.pool.sqrtPriceX96,
            params.initializedTick.getSqrtRatioAtTick(),
            self.orderPools[0].sellRateCurrent,
            self.orderPools[1].sellRateCurrent
        );
        // cross tick
        updatedPool = advanceToNewTimestamp(
            self,
            AdvanceParams(
                params.nextTimestamp - (params.secondsElapsed - secondsUntilCrossing),
                secondsUntilCrossing,
                params.pool,
                true
            ),
            ticks,
            tickBitmap
        );
        int128 liquidityNet = ticks[params.initializedTick].liquidityNet;
        updatedPool.sqrtPriceX96 = params.initializedTick.getSqrtRatioAtTick();
        updatedPool.liquidity = liquidityNet < 0
            ? updatedPool.liquidity - uint128(-liquidityNet)
            : updatedPool.liquidity + uint128(liquidityNet);

        // continue to expiry
        updatedPool = advanceToNewTimestamp(
            self,
            AdvanceParams(params.nextTimestamp, params.secondsElapsed - secondsUntilCrossing, updatedPool, false),
            ticks,
            tickBitmap
        );
    }

    function getNextInitializedTick(
        PoolParamsOnExecute memory pool,
        uint160 nextSqrtPriceX96,
        mapping(int16 => uint256) storage tickBitmap
    ) private returns (bool initialized, int24 nextTickInit) {
        nextTickInit = pool.sqrtPriceX96.getTickAtSqrtRatio();
        bool searchingLeft = nextSqrtPriceX96 < pool.sqrtPriceX96;
        int24 targetTick = nextSqrtPriceX96.getTickAtSqrtRatio();

        while (!searchingLeft ? nextTickInit < targetTick : nextTickInit > targetTick) {
            if (searchingLeft) nextTickInit -= 1;
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
}
