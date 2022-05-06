// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title LimitOrder
/// @notice LimitOrders represent an owner address' limit order to execute at a given tick
library LimitOrder {

    // info stored for each user's order
    struct Info {
        // the amount of liquidity to trade in this order
        uint128 liquidity;
    }

    /// @notice Returns the Info struct of a limit order
    /// @param self The mapping containing all user limit orders
    /// @param owner The address of the order owner
    /// @param tick The tick of the limit order
    /// @param cycle The cycle the limit order will execute on
    /// @return limitOrder The limit order info struct of the given owners' limit order
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 tick,
        uint128 cycle
    ) internal view returns (Info storage limitOrder) {
        limitOrder = self[keccak256(abi.encodePacked(owner, tick, cycle))];
    }

    function addLiquidity(
        Info storage limitOrder,
        uint128 amount
    ) internal {
        limitOrder.liquidity += amount;
    }
}
