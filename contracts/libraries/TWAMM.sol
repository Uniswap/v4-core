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
    }

    struct OrderPool {
      mapping(uint256 => Order) orders;
    }

    /// @notice information associated with a long term order
    struct Order {
        uint256 expiration;
        uint256 saleRate;
        address owner;
    }

    struct LongTermOrderParams {
      bool zeroForOne;
      address owner;
      uint256 amountIn;
      uint256 expiration; // would adjust to nearest beforehand expiration interval
    }

    function submitLongTermOrder(LongTermOrders storage self, LongTermOrderParams calldata params) internal returns (uint256 tokenId) {
      uint8 tokenIndex = params.zeroForOne ? 0 : 1;

      // playing with deterministic ID?? would mean combining any new orders with same owner/expiration
      tokenId = uint256(keccak256(abi.encode(params.expiration, params.owner))); // TODO: update expiration if its not at interval

      uint256 saleRate = params.amountIn / (params.expiration - block.timestamp);

      self.orderPools[tokenIndex].orders[tokenId] = Order({
        owner: params.owner,
        expiration: params.expiration,
        saleRate: saleRate
      });
    }
}
