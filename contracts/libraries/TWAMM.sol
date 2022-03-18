// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Tick} from './Tick.sol';
import {OrderPool} from './TWAMM/OrderPool.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {SafeCast} from './SafeCast.sol';
import {ABDKMathQuad} from 'abdk-libraries-solidity/ABDKMathQuad.sol';
import 'hardhat/console.sol';

/// @title TWAMM - Time Weighted Average Market Maker
/// @notice TWAMM represents long term orders in a pool
library TWAMM {
    using ABDKMathQuad for *;
    using SafeCast for *;
    using OrderPool for OrderPool.State;

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

    /// @notice Contains full state related to long term orders
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
        if (params.expiration % self.expirationInterval != 0) {
            revert ExpirationNotOnInterval(params.expiration);
        }

        // TODO: bump twamm order state
        orderId = self.nextId++;

        uint8 sellTokenIndex = params.zeroForOne ? 0 : 1;
        // TODO: refine math?
        uint256 sellRate = params.amountIn / (params.expiration - block.timestamp);

        self.orderPools[sellTokenIndex].sellRateCurrent += sellRate;
        // TODO: update expiration if its not at interval (alternatively could take n intervals as param, this
        // felt more deterministic though)
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
        returns (
            uint256 unsoldAmount,
            uint256 purchasedAmount,
            uint8 sellTokenIndex
        )
    {
        // TODO: bump TWAMM order state
        Order memory order = self.orders[orderId];
        if (order.owner != msg.sender) revert MustBeOwner(orderId, order.owner, msg.sender);
        if (order.expiration <= block.timestamp)
            revert OrderAlreadyCompleted(orderId, order.expiration, block.timestamp);

        (unsoldAmount, purchasedAmount) = calculateCancellationAmounts(order);

        sellTokenIndex = order.sellTokenIndex;

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
            uint256 earningsFactorAtExpiration = orderPool.earningsFactorAtInterval[order.expiration];
            // TODO: math to be refined
            earningsAmount =
                ((earningsFactorAtExpiration - order.unclaimedEarningsFactor) * order.sellRate) >>
                FixedPoint96.RESOLUTION;
            // clear stake
            self.orders[orderId].unclaimedEarningsFactor = 0;
        } else {
            // TODO: math to be refined, divide by 2**96 bc its represented as fixedPointX96
            // TODO: set the earningsFactor
            earningsAmount =
                ((orderPool.earningsFactorCurrent - order.unclaimedEarningsFactor) * order.sellRate) >>
                FixedPoint96.RESOLUTION;
            self.orders[orderId].unclaimedEarningsFactor = orderPool.earningsFactorCurrent;
        }
    }

    struct PoolParamsOnExecute {
        uint160 sqrtPriceX96;
        uint128 liquidity;
    }

    struct OrderPoolParamsOnExecute {
        uint256 sellRateCurrent0;
        uint256 sellRateCurrent1;
    }

    function executeTWAMMOrders(
        State storage self,
        PoolParamsOnExecute memory poolParams,
        mapping(int24 => Tick.Info) storage ticks
    ) internal {
        uint256 prevTimestamp = self.lastVirtualOrderTimestamp;
        uint256 nextExpirationTimestamp = self.lastVirtualOrderTimestamp +
            (self.expirationInterval - (self.lastVirtualOrderTimestamp % self.expirationInterval));

        while (nextExpirationTimestamp <= block.timestamp) {
            // skip calculations on intervals that don't have any expirations
            // TODO: potentially optimize with bitmap of initialized intervals
            if (
                self.orderPools[0].sellRateEndingAtInterval[nextExpirationTimestamp] > 0 ||
                self.orderPools[1].sellRateEndingAtInterval[nextExpirationTimestamp] > 0
            ) {
                (uint160 newSqrtPriceX96, uint256 earningsPool0, uint256 earningsPool1) = calculateExecutionUpdates(
                    nextExpirationTimestamp - prevTimestamp,
                    poolParams,
                    OrderPoolParamsOnExecute(self.orderPools[0].sellRateCurrent, self.orderPools[1].sellRateCurrent),
                    ticks
                );

                // update order pools
                self.orderPools[0].advanceToInterval(nextExpirationTimestamp, earningsPool0);
                self.orderPools[1].advanceToInterval(nextExpirationTimestamp, earningsPool1);
                // update values in memory
                poolParams.sqrtPriceX96 = newSqrtPriceX96;
                prevTimestamp = nextExpirationTimestamp;
            }
            nextExpirationTimestamp += self.expirationInterval;
        }

        if (nextExpirationTimestamp > block.timestamp) {
            (uint160 newSqrtPriceX96, uint256 earningsPool0, uint256 earningsPool1) = calculateExecutionUpdates(
                block.timestamp - prevTimestamp,
                poolParams,
                OrderPoolParamsOnExecute(self.orderPools[0].sellRateCurrent, self.orderPools[1].sellRateCurrent),
                ticks
            );
            self.orderPools[0].advanceToCurrentTime(earningsPool0);
            self.orderPools[1].advanceToCurrentTime(earningsPool1);
        }
    }

    function calculateExecutionUpdates(
        uint256 secondsElapsed,
        PoolParamsOnExecute memory poolParams,
        OrderPoolParamsOnExecute memory orderPoolParams,
        mapping(int24 => Tick.Info) storage ticks
    )
        internal
        returns (
            uint160 sqrtPriceX96,
            uint256 earningsPool0,
            uint256 earningsPool1
        )
    {
        // https://www.desmos.com/calculator/yr3qvkafvy
        // https://www.desmos.com/calculator/rjcdwnaoja -- tracks some intermediate calcs
        // TODO:
        // -- Need to incorporate ticks
        // -- perform calcs when a sellpool is 0
        // -- update TWAP

        bytes16 sellRatio = orderPoolParams.sellRateCurrent1.fromUInt().div(
            orderPoolParams.sellRateCurrent0.fromUInt()
        );

        bytes16 sqrtSellRate = orderPoolParams
            .sellRateCurrent0
            .fromUInt()
            .mul(orderPoolParams.sellRateCurrent1.fromUInt())
            .sqrt();

        bytes16 newSqrtPriceX96 = calculateNewSqrtPriceX96(sellRatio, sqrtSellRate, secondsElapsed, poolParams);

        EarningsFactorParams memory earningsFactorParams = EarningsFactorParams({
            secondsElapsed: secondsElapsed.fromUInt(),
            sellRatio: sellRatio,
            sqrtSellRate: sqrtSellRate,
            prevSqrtPriceX96: poolParams.sqrtPriceX96.fromUInt(),
            newSqrtPriceX96: newSqrtPriceX96,
            liquidity: poolParams.liquidity.fromUInt()
        });

        sqrtPriceX96 = newSqrtPriceX96.toUInt().toUint160();
        earningsPool0 = getEarningsAmountPool0(earningsFactorParams).toUInt();
        earningsPool1 = getEarningsAmountPool1(earningsFactorParams).toUInt();
    }

    struct EarningsFactorParams {
        bytes16 secondsElapsed;
        bytes16 sellRatio;
        bytes16 sqrtSellRate;
        bytes16 prevSqrtPriceX96;
        bytes16 newSqrtPriceX96;
        bytes16 liquidity;
    }

    function getEarningsAmountPool0(EarningsFactorParams memory params) private returns (bytes16 earningsFactor) {
        bytes16 minuend = params.sellRatio.mul(FixedPoint96.Q96.fromUInt()).mul(params.secondsElapsed);
        bytes16 subtrahend = params
            .liquidity
            .mul(params.sellRatio.sqrt())
            .mul(params.newSqrtPriceX96.sub(params.prevSqrtPriceX96))
            .div(params.sqrtSellRate);
        return minuend.sub(subtrahend);
    }

    function getEarningsAmountPool1(EarningsFactorParams memory params) private returns (bytes16 earningsFactor) {
        bytes16 minuend = params.secondsElapsed.div(params.sellRatio);
        bytes16 subtrahend = params
            .liquidity
            .mul(reciprocal(params.sellRatio.sqrt()))
            .mul(
                reciprocal(params.newSqrtPriceX96).mul(FixedPoint96.Q96.fromUInt()).sub(
                    reciprocal(params.prevSqrtPriceX96).mul(FixedPoint96.Q96.fromUInt())
                )
            )
            .div(params.sqrtSellRate);
        return minuend.sub(subtrahend).mul(FixedPoint96.Q96.fromUInt());
    }

    function calculateNewSqrtPriceX96(
        bytes16 sellRatio,
        bytes16 sqrtSellRate,
        uint256 secondsElapsed,
        PoolParamsOnExecute memory poolParams
    ) private returns (bytes16 newSqrtPriceX96) {
        bytes16 sqrtSellRatioX96 = sellRatio.sqrt().mul(FixedPoint96.Q96.fromUInt());

        bytes16 pow = uint256(2).fromUInt().mul(sqrtSellRate).mul((secondsElapsed).fromUInt()).div(
            poolParams.liquidity.fromUInt()
        );

        bytes16 c = sqrtSellRatioX96.sub(poolParams.sqrtPriceX96.fromUInt()).div(
            sqrtSellRatioX96.add(poolParams.sqrtPriceX96.fromUInt())
        );

        newSqrtPriceX96 = sqrtSellRatioX96.mul(pow.exp().sub(c)).div(pow.exp().add(c));
    }

    function reciprocal(bytes16 n) private returns (bytes16) {
        return uint256(1).fromUInt().div(n);
    }

    function calculateCancellationAmounts(Order memory order)
        private
        returns (uint256 unsoldAmount, uint256 purchasedAmount)
    {
        // TODO: actually calculate this
        unsoldAmount = 111;
        purchasedAmount = 222;
    }
}
