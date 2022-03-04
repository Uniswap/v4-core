// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {FullMath} from './FullMath.sol';
import {FixedPoint128} from './FixedPoint128.sol';

/// @title TWAMM - Time Weighted Average Market Maker
/// @notice TWAMM represents long term orders in a pool
library TWAMM {
    ///@notice structure contains full state related to long term orders
    struct LongTermOrders {
        /// @notice minimum interval in seconds between order expiries
        uint256 minimumInterval;
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
        uint256 sellingRate;
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

    function submitLongTermOrder(LongTermOrders storage self, LongTermOrderParams calldata params)
        internal
        returns (uint256 orderId)
    {
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
    }
}
