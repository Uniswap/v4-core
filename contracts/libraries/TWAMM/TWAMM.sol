// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Tick} from '../Tick.sol';
import {TickBitmap} from '../TickBitmap.sol';
import {OrderPool} from './OrderPool.sol';
import {TwammMath} from './TwammMath.sol';
import {FixedPoint96} from '../FixedPoint96.sol';
import {SwapMath} from '../SwapMath.sol';
import 'hardhat/console.sol';

/// @title TWAMM - Time Weighted Average Market Maker
/// @notice TWAMM represents long term orders in a pool
library TWAMM {
    using OrderPool for OrderPool.State;
    using TickBitmap for mapping(int16 => uint256);

    /// @notice Thrown when account other than owner attempts to interact with an order
    /// @param orderId The orderId
    /// @param owner The owner of the order
    /// @param currentAccount The invalid account attempting to interact with the order
    error MustBeOwner(uint256 orderId, address owner, address currentAccount);

    /// @notice Thrown when trying to cancel an already completed order
    /// @param orderId The orderId
    /// @param expiration The expiration timestamp of the order
    /// @param currentTime The current block timestamp
    error OrderAlreadyCompleted(uint256 orderId, uint256 expiration, uint256 currentTime);

    /// @notice Thrown when trying to submit an order with an expiration that isn't on the interval.
    /// @param expiration The expiration timestamp of the order
    error ExpirationNotOnInterval(uint256 expiration);

    /// @notice Thrown when trying to submit an order with an expiration time in the past.
    /// @param expiration The expiration timestamp of the order
    error ExpirationLessThanBlocktime(uint256 expiration);

    /// @notice Thrown when trying to submit an order without initializing TWAMM state first
    error NotInitialized();

    /// @notice Contains full state related to the TWAMM
    /// @member expirationInterval Interval in seconds between valid order expiration timestamps
    /// @member lastVirtualOrderTimestamp Last timestamp in which virtual orders were executed
    /// @member orderPools Mapping from token index (0 and 1) to OrderPool that is selling that token
    /// @member orders Mapping of orderId to individual orders
    /// @member nextId Id for next submitted order
    struct State {
        uint256 expirationInterval;
        uint256 lastVirtualOrderTimestamp;
        uint256 nextId;
        mapping(uint8 => OrderPool.State) orderPools;
        mapping(uint256 => Order) orders;
    }

    /// @notice Information associated with a long term order
    /// @member sellTokenIndex Index of sell token, 0 for token0, 1 for token1
    /// @member owner Owner of the order
    /// @member expiration Timestamp when the order expires
    /// @member sellRate Amount of tokens sold per interval
    /// @member unclaimedEarningsFactor The accrued earnings factor from which to start claiming owed earnings for this order
    struct Order {
        uint8 sellTokenIndex;
        address owner;
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
        returns (uint256 orderId)
    {
        if (self.expirationInterval == 0) {
            revert NotInitialized();
        }
        if (params.expiration < block.timestamp) {
            revert ExpirationLessThanBlocktime(params.expiration);
        }
        if (params.expiration % self.expirationInterval != 0) {
            revert ExpirationNotOnInterval(params.expiration);
        }

        orderId = self.nextId++;

        uint8 sellTokenIndex = params.zeroForOne ? 0 : 1;
        uint256 sellRate = params.amountIn / (params.expiration - block.timestamp);

        self.orderPools[sellTokenIndex].sellRateCurrent += sellRate;
        self.orderPools[sellTokenIndex].sellRateEndingAtInterval[params.expiration] += sellRate;

        self.orders[orderId] = Order({
            owner: params.owner,
            expiration: params.expiration,
            sellRate: sellRate,
            sellTokenIndex: sellTokenIndex,
            unclaimedEarningsFactor: self.orderPools[sellTokenIndex].earningsFactorCurrent
        });
    }

    /// @notice Cancels a long term order and updates procceeds owed in both tokens
    ///   back to the owner
    /// @param orderId The ID of the order to be cancelled
    function cancelLongTermOrder(State storage self, uint256 orderId)
        internal
        returns (uint256 amountOut0, uint256 amountOut1)
    {
        Order memory order = self.orders[orderId];
        if (order.owner != msg.sender) revert MustBeOwner(orderId, order.owner, msg.sender);
        if (order.expiration <= block.timestamp)
            revert OrderAlreadyCompleted(orderId, order.expiration, block.timestamp);

        uint256 earningsFactorCurrent = self.orderPools[order.sellTokenIndex].earningsFactorCurrent;
        (amountOut0, amountOut1) = calculateCancellationAmounts(earningsFactorCurrent, order);
        if (order.sellTokenIndex == 1) (amountOut1, amountOut0) = (amountOut0, amountOut1);

        self.orders[orderId].sellRate = 0;
        self.orderPools[order.sellTokenIndex].sellRateCurrent -= order.sellRate;
        self.orderPools[order.sellTokenIndex].sellRateEndingAtInterval[order.expiration] -= order.sellRate;
    }

    /// @notice Claim earnings from an ongoing or expired order
    /// @param orderId The ID of the order to be claimed
    function claimEarnings(State storage self, uint256 orderId)
        internal
        returns (uint256 earningsAmount, uint8 sellTokenIndex)
    {
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
    }

    struct OrderPoolParamsOnExecute {
        uint256 sellRateCurrent0;
        uint256 sellRateCurrent1;
    }

    /// @notice Executes all existing long term orders in the TWAMM
    /// @param poolParams The relevant state of the pool
    /// @param ticks Points to tick information on the pool
    function executeTWAMMOrders(
        State storage self,
        PoolParamsOnExecute memory poolParams,
        mapping(int24 => Tick.Info) storage ticks,
        mapping(int16 => uint256) storage tickBitmap
    )
        internal
        returns (
            bool zeroForOne,
            uint256 swapAmountIn,
            uint160 newSqrtPriceX96
        )
    {
        if (self.orderPools[0].sellRateCurrent == 0 && self.orderPools[1].sellRateCurrent == 0) {
            self.lastVirtualOrderTimestamp = block.timestamp;
            return (false, 0, 0);
        }

        uint256 currentTimestamp = block.timestamp;
        /* uint256 nextInitializedSqrtPriceX96 = tickBitmap.nextInitializedTickWithinOneWord); */
        uint160 prevSqrtPriceX96 = poolParams.sqrtPriceX96;
        uint256 prevTimestamp = self.lastVirtualOrderTimestamp;
        uint256 nextExpirationTimestamp = self.lastVirtualOrderTimestamp +
            (self.expirationInterval - (self.lastVirtualOrderTimestamp % self.expirationInterval));

        while (nextExpirationTimestamp <= currentTimestamp) {
            // skip calculations on intervals that don't have any expirations
            // TODO: potentially optimize with bitmap of initialized intervals
            if (
                self.orderPools[0].sellRateEndingAtInterval[nextExpirationTimestamp] > 0 ||
                self.orderPools[1].sellRateEndingAtInterval[nextExpirationTimestamp] > 0
            ) {
                uint160 nextSqrtPriceX96 = advanceToNewTimestamp(
                    self,
                    nextExpirationTimestamp,
                    nextExpirationTimestamp - prevTimestamp,
                    poolParams,
                    ticks
                );
                poolParams.sqrtPriceX96 = nextSqrtPriceX96;
                prevTimestamp = nextExpirationTimestamp;
            }
            nextExpirationTimestamp += self.expirationInterval;
        }

        if (prevTimestamp < currentTimestamp) {
            poolParams.sqrtPriceX96 = advanceToNewTimestamp(
                self,
                currentTimestamp,
                currentTimestamp - prevTimestamp,
                poolParams,
                ticks
            );
        }

        self.lastVirtualOrderTimestamp = currentTimestamp;

        (, swapAmountIn, , ) = SwapMath.computeSwapStep(
            prevSqrtPriceX96,
            poolParams.sqrtPriceX96,
            poolParams.liquidity,
            type(int256).max,
            poolParams.fee
        );
        zeroForOne = prevSqrtPriceX96 > newSqrtPriceX96;
    }

    function advanceToNewTimestamp(
        State storage self,
        uint256 nextTimestamp,
        uint256 secondsElapsed,
        PoolParamsOnExecute memory poolParams,
        mapping(int24 => Tick.Info) storage ticks
    ) private returns (uint160) {
        (uint160 nextSqrtPriceX96, uint256 earningsPool0, uint256 earningsPool1) = TwammMath.calculateExecutionUpdates(
            secondsElapsed,
            poolParams,
            OrderPoolParamsOnExecute(self.orderPools[0].sellRateCurrent, self.orderPools[1].sellRateCurrent),
            ticks
        );

        if (nextTimestamp % self.expirationInterval == 0) {
            self.orderPools[0].advanceToInterval(nextTimestamp, earningsPool0);
            self.orderPools[1].advanceToInterval(nextTimestamp, earningsPool1);
        } else {
            self.orderPools[0].advanceToCurrentTime(earningsPool0);
            self.orderPools[1].advanceToCurrentTime(earningsPool1);
        }

        return nextSqrtPriceX96;
    }

    function calculateCancellationAmounts(uint256 earningsFactorCurrent, Order memory order)
        private
        returns (uint256 unsoldAmount, uint256 purchasedAmount)
    {
        unsoldAmount = order.sellRate * (order.expiration - block.timestamp);
        uint256 earningsFactor = (earningsFactorCurrent - order.unclaimedEarningsFactor);
        purchasedAmount = (earningsFactor * order.sellRate) >> FixedPoint96.RESOLUTION;
    }
}
