// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Tick} from './Tick.sol';
import {FixedPoint96} from './FixedPoint96.sol';
import {SafeCast} from './SafeCast.sol';
import {ABDKMathQuad} from 'abdk-libraries-solidity/ABDKMathQuad.sol';
import 'hardhat/console.sol';

/// @title TWAMM - Time Weighted Average Market Maker
/// @notice TWAMM represents long term orders in a pool
library TWAMM {
    using ABDKMathQuad for *;
    using SafeCast for *;

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
        mapping(uint8 => OrderPool) orderPools;
        mapping(uint256 => Order) orders;
    }

    /// @notice Information related to a long term order pool
    /// @member sellRate The total current sell rate among all orders
    /// @member sellRateEndingAtInterval Mapping (timestamp => sellRate) The amount of expiring sellRate at this interval
    /// @member earningsFactor Sum of (salesEarnings_k / salesRate_k) over every period k.
    /// @member earningsFactorAtInterval Mapping (timestamp => sellRate) The earnings factor accrued by a certain time interval
    struct OrderPool {
        uint256 sellRate;
        mapping(uint256 => uint256) sellRateEndingAtInterval;
        //
        uint256 earningsFactor;
        mapping(uint256 => uint256) earningsFactorAtInterval;
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
        // TODO: bump twamm order state
        orderId = self.nextId++;

        uint8 sellTokenIndex = params.zeroForOne ? 0 : 1;
        // TODO: refine math?
        uint256 sellRate = params.amountIn / (params.expiration - block.timestamp);

        self.orderPools[sellTokenIndex].sellRate += sellRate;
        // TODO: update expiration if its not at interval (alternatively could take n intervals as param, this
        // felt more deterministic though)
        self.orderPools[sellTokenIndex].sellRateEndingAtInterval[params.expiration] += sellRate;

        self.orders[orderId] = Order({
            owner: params.owner,
            expiration: params.expiration,
            sellRate: sellRate,
            sellTokenIndex: sellTokenIndex,
            unclaimedEarningsFactor: self.orderPools[sellTokenIndex].earningsFactor
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
        self.orderPools[sellTokenIndex].sellRate -= order.sellRate;
        self.orderPools[sellTokenIndex].sellRateEndingAtInterval[order.expiration] -= order.sellRate;
    }

    /// @notice Claim earnings from an ongoing or expired order
    /// @param orderId The ID of the order to be claimed
    function claimEarnings(State storage self, uint256 orderId)
        internal
        returns (uint256 earningsAmount, uint8 sellTokenIndex)
    {
        Order memory order = self.orders[orderId];
        sellTokenIndex = order.sellTokenIndex;
        OrderPool storage orderPool = self.orderPools[sellTokenIndex];

        if (block.timestamp > order.expiration) {
            uint256 earningsFactorAtExpiration = orderPool.earningsFactorAtInterval[order.expiration];
            // TODO: math to be refined
            earningsAmount = (earningsFactorAtExpiration - order.unclaimedEarningsFactor) * order.sellRate;
        } else {
            // TODO: math to be refined
            earningsAmount = (orderPool.earningsFactor - order.unclaimedEarningsFactor) * order.sellRate;
            self.orders[orderId].unclaimedEarningsFactor = orderPool.earningsFactor;
        }
    }

    struct PoolParamsOnExecute {
        uint8 feeProtocol;
        uint160 sqrtPriceX96;
        uint128 liquidity;
    }

    struct OrderPoolParamsOnExecute {
        uint256 orderPool0SellRate;
        uint256 orderPool1SellRate;
    }

    function executeTWAMMOrders(
        State storage self,
        PoolParamsOnExecute memory poolParams,
        mapping(int24 => Tick.Info) storage ticks
    ) internal {
        // TODO: (cleanup) return numbers that will guide the new pool state...update that in pool or pool manager.
        // ideally if ticks are needed, would just be for read purposes

        uint256 prevTimestamp = self.lastVirtualOrderTimestamp;
        uint256 nextExpirationTimestamp = self.lastVirtualOrderTimestamp +
            (self.expirationInterval - (self.lastVirtualOrderTimestamp % self.expirationInterval));

        while (nextExpirationTimestamp < block.timestamp) {
            // skip calculations on intervals that don't have any expirations
            if (
                self.orderPools[0].sellRateEndingAtInterval[nextExpirationTimestamp] > 0 ||
                self.orderPools[1].sellRateEndingAtInterval[nextExpirationTimestamp] > 0
            ) {
                (
                    uint160 newSqrtPriceX96,
                    uint256 earningsFactorPool0,
                    uint256 earningsFactorPool1
                ) = calculateTWAMMExecutionUpdates(
                        prevTimestamp,
                        nextExpirationTimestamp,
                        poolParams,
                        OrderPoolParamsOnExecute(self.orderPools[0].sellRate, self.orderPools[1].sellRate),
                        ticks
                    );

                // update order pools
                self.orderPools[0].earningsFactorAtInterval[nextExpirationTimestamp] += earningsFactorPool0;
                self.orderPools[1].earningsFactorAtInterval[nextExpirationTimestamp] += earningsFactorPool1;
                self.orderPools[0].sellRate -= self.orderPools[0].sellRateEndingAtInterval[nextExpirationTimestamp];
                self.orderPools[1].sellRate -= self.orderPools[1].sellRateEndingAtInterval[nextExpirationTimestamp];

                poolParams.sqrtPriceX96 = newSqrtPriceX96; // update pool price for next iteration
                prevTimestamp = nextExpirationTimestamp; // if we did a calculation, update prevTimestamp
            }
            nextExpirationTimestamp += self.expirationInterval;
        }

        if (prevTimestamp != block.timestamp) {
            (
                uint160 newSqrtPriceX96,
                uint256 earningsFactorPool0,
                uint256 earningsFactorPool1
            ) = calculateTWAMMExecutionUpdates(
                    prevTimestamp,
                    nextExpirationTimestamp,
                    poolParams,
                    OrderPoolParamsOnExecute(self.orderPools[0].sellRate, self.orderPools[1].sellRate),
                    ticks
                );
        }
    }

    function calculateTWAMMExecutionUpdates(
        uint256 startingTimestamp,
        uint256 endingTimeStamp,
        PoolParamsOnExecute memory poolParams,
        OrderPoolParamsOnExecute memory orderPoolParams,
        mapping(int24 => Tick.Info) storage ticks
    )
        internal
        returns (
            uint160 sqrtPriceX96,
            uint256 earningsFactorPool0,
            uint256 earningsFactorPool1
        )
    {
        // https://www.desmos.com/calculator/yr3qvkafvy
        // TODO: Need to incorporate ticks + update TWAP as well + refine math
        bytes16 sqrtSellRatioX96 = orderPoolParams
            .orderPool1SellRate
            .fromUInt()
            .div(orderPoolParams.orderPool0SellRate.fromUInt())
            .sqrt()
            .mul(FixedPoint96.Q96.fromUInt());
        bytes16 sqrtSellRate = orderPoolParams
            .orderPool0SellRate
            .fromUInt()
            .mul(orderPoolParams.orderPool1SellRate.fromUInt())
            .sqrt();

        // corrrect
        bytes16 c = sqrtSellRatioX96.sub(poolParams.sqrtPriceX96.fromUInt()).div(
            sqrtSellRatioX96.add(poolParams.sqrtPriceX96.fromUInt())
        );
        // correct
        bytes16 pow = uint256(2).fromUInt().mul(sqrtSellRate).mul((endingTimeStamp - startingTimestamp).fromUInt()).div(
            poolParams.liquidity.fromUInt()
        );

        // correct
        bytes16 numerator = pow.exp().sub(c);
        bytes16 denominator = pow.exp().add(c);

        bytes16 newSqrtPriceX96 = sqrtSellRatioX96.mul(numerator).div(denominator);

        // tracking intermediate calculations here: https://www.desmos.com/calculator/rjcdwnaoja

        console.log('c:');
        console.logInt(c.mul(uint256(100000).fromUInt()).toInt());

        console.log('pow:');
        console.log(pow.mul(uint256(100000).fromUInt()).toUInt());

        console.log('final: ');
        console.log(newSqrtPriceX96.toUInt());

        // TODO: For now give sold amount as earnings to opposite pool. Then take amount out from after swap and assign that
        // to the corresponding pool. (unless I can get that number amountOut through pure calculation but seems hard)
        earningsFactorPool0 = (endingTimeStamp - startingTimestamp) * orderPoolParams.orderPool1SellRate;
        earningsFactorPool1 = (endingTimeStamp - startingTimestamp) * orderPoolParams.orderPool0SellRate;
        sqrtPriceX96 = newSqrtPriceX96.toUInt().toUint160();
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
