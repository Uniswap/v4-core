// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {FullMath} from './FullMath.sol';
import {FixedPoint128} from './FixedPoint128.sol';

/// @title TWAMM - Time Weighted Average Market Maker
/// @notice TWAMM represents long term orders in a pool
library TWAMM {
    /// @notice Thrown when account other than owner attempts to interact with an order
    /// @param orderId The orderId
    /// @param owner The owner of the order
    /// @param currentAccount The invalid account attempting to interact with the order
    error MustBeOwner(uint256 orderId, address owner, address currentAccount);

    /// @notice Thrown when account other than owner attempts to interact with an order
    /// @param orderId The orderId
    /// @param expiration The expiration timestamp of the order
    /// @param currentTime The current block timestamp
    error OrderAlreadyCompleted(uint256 orderId, uint256 expiration, uint256 currentTime);

    /// @notice structure contains full state related to long term orders
    struct State {
        /// @notice interval in seconds between valie order expiry timestamps
        uint256 expiryInterval;
        /// @notice last virtual orders were executed immediately before this block
        uint256 lastVirtualOrderTimestamp;
        /// @notice mapping from token index (0 and 1) to OrderPool that is selling that token
        mapping(uint8 => OrderPool) orderPools;
        /// @notice mapping to individual orders
        mapping(uint256 => Order) orders;
        /// @notice nextId Id for next order
        uint256 nextId;
    }

    struct OrderPool {
        /// @notice the total current selling rate
        uint256 sellingRate;
        /// @notice (timestamp => salesRate) The amount of expiring salesRate at this interval
        mapping(uint256 => uint256) salesRateEndingPerInterval;
    }

    /// @notice information associated with a long term order
    struct Order {
        bool zeroForOne;
        address owner;
        uint256 expiration;
        uint256 sellingRate;
    }

    struct LongTermOrderParams {
        bool zeroForOne;
        address owner;
        uint256 amountIn;
        uint256 expiration; // would adjust to nearest beforehand expiration interval
    }

    function initialize(State storage self, uint256 expiryInterval) internal {
        self.expiryInterval = expiryInterval;
        self.lastVirtualOrderTimestamp = block.timestamp; // TODO: could make this a nice even number? (multiple of 1000)
    }

    function submitLongTermOrder(State storage self, LongTermOrderParams calldata params)
        internal
        returns (uint256 orderId)
    {
        // TODO: bump twamm order state
        orderId = self.nextId++;

        uint8 tokenIndex = params.zeroForOne ? 0 : 1;
        uint256 sellingRate = params.amountIn / (params.expiration - block.timestamp);

        // TODO: update expiration if its not at interval
        self.orders[orderId] = Order({
            owner: params.owner,
            expiration: params.expiration,
            sellingRate: sellingRate,
            zeroForOne: params.zeroForOne
        });

        self.orderPools[tokenIndex].sellingRate += sellingRate;
        self.orderPools[tokenIndex].salesRateEndingPerInterval[params.expiration] += sellingRate;
    }

    function cancelLongTermOrder(State storage self, uint256 orderId)
        internal
        returns (uint256 unsoldAmount, uint256 purchasedAmount)
    {
        // TODO: bump TWAMM order state
        Order memory order = self.orders[orderId];
        if (order.owner != msg.sender) revert MustBeOwner(orderId, order.owner, msg.sender);
        if (order.expiration <= block.timestamp)
            revert OrderAlreadyCompleted(orderId, order.expiration, block.timestamp);

        (unsoldAmount, purchasedAmount) = calculateCancellationAmounts(order);

        uint8 tokenIndex = order.zeroForOne ? 0 : 1;
        self.orderPools[tokenIndex].sellingRate -= order.sellingRate;
        self.orderPools[tokenIndex].salesRateEndingPerInterval[order.expiration] -= order.sellingRate;
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
