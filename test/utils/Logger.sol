// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";

import "forge-std/console2.sol";

// Useful for printing out the true values in a fuzz. For failing fuzzes, foundry logs the unsanitized params.
contract Logger {
    function logParams(IPoolManager.ModifyLiquidityParams memory params) public {
        console2.log("ModifyLiquidity.tickLower", params.tickLower);
        console2.log("ModifyLiquidity.tickUpper", params.tickUpper);
        console2.log("ModifyLiquidity.liquidityDelta", params.liquidityDelta);
        console2.log("ModifyLiquidity.salt");
        console2.logBytes32(params.salt);
    }
}
