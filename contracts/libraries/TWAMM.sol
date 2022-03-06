// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

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


    /// @notice Contains full state related to long term orders
    /// @member expirationInterval Interval in seconds between valid order expiration timestamps
    /// @member lastVirtualOrderTimestamp Last timestamp in which virtual orders were executed
    /// @member orderPools Mapping from token index (0 and 1) to OrderPool that is selling that token
    /// @member orders Mapping of orderId to individual orders
    /// @member nextId Id for next submitted order
    struct State {
        uint256 expirationInterval;
        uint256 lastVirtualOrderTimestamp;
        mapping(uint8 => OrderPool) orderPools;
        mapping(uint256 => Order) orders;
        uint256 nextId;
    }

    /// @notice Information associated with a long term order pool
    /// @member sellRate The total current sell rate among all orders
    /// @member earningsFactor Sum of (salesEarnings_k / salesRate_k) over every period k.
    /// @member sellRateEndingPerInterval Mapping (timestamp => sellRate) The amount of expiring sellRate at this interval
    /// @member earningsFactorAtInterval Mapping (timestamp => sellRate) The earnings factor accrued by a certain time interval
    struct OrderPool {
        uint256 sellRate;
        uint256 earningsFactor;
        mapping(uint256 => uint256) sellRateEndingPerInterval;
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
        uint256 sellRate = params.amountIn / (params.expiration - block.timestamp);

        self.orderPools[sellTokenIndex].sellRate += sellRate;
        self.orderPools[sellTokenIndex].sellRateEndingPerInterval[params.expiration] += sellRate;

        // TODO: update expiration if its not at interval
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
        returns (uint256 unsoldAmount, uint256 purchasedAmount)
    {
        // TODO: bump TWAMM order state
        Order memory order = self.orders[orderId];
        if (order.owner != msg.sender) revert MustBeOwner(orderId, order.owner, msg.sender);
        if (order.expiration <= block.timestamp)
            revert OrderAlreadyCompleted(orderId, order.expiration, block.timestamp);

        (unsoldAmount, purchasedAmount) = calculateCancellationAmounts(order);

        self.orderPools[order.sellTokenIndex].sellRate -= order.sellRate;
        self.orderPools[order.sellTokenIndex].sellRateEndingPerInterval[order.expiration] -= order.sellRate;
    }

    /// @notice Claim earnings from an ongoing or expired order
    /// @param orderId The ID of the order to be claimed
    function claimEarnings(State storage self, uint256 orderId) internal returns (uint256 claimedAmount) {
      Order memory order = self.orders[orderId];
      OrderPool storage orderPool = self.orderPools[order.sellTokenIndex];

      if (block.timestamp > order.expiration) {
          uint256 earningsFactorAtExpiration = orderPool.earningsFactorAtInterval[order.expiration];
          // TODO: math to be refined
          claimedAmount = (earningsFactorAtExpiration - order.unclaimedEarningsFactor) * order.sellRate;
      }
      //if order has not yet expired, we just adjust the start
      else {
          // TODO: math to be refined
          claimedAmount = (orderPool.earningsFactor - order.unclaimedEarningsFactor) * order.sellRate;
          self.orders[orderId].unclaimedEarningsFactor = orderPool.earningsFactor;
      }
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
