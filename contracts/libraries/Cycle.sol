// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library Cycle {

    // info stored for each user's position
    struct Info {
        // the amount of limit liquidity in this tick and cycle
        uint128 limitLiquidity;
    }

    /// @notice Returns the Info struct of a cycle, given the tick and cycle number
    /// @param self The mapping containing all cycles
    /// @param tick The tick of the cycle
    /// @param cycleNumber The cycle number of that tick
    /// @return cycle The Info struct of the given tick's cycle
    function get(
        mapping(bytes32 => Info) storage self,
        int24 tick,
        uint128 cycleNumber
    ) internal view returns (Cycle.Info storage cycle) {
        cycle = self[keccak256(abi.encodePacked(tick, cycleNumber))];
    }

}