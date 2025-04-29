// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {ModifyLiquidityParams} from "../../src/types/PoolOperation.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {StateLibrary} from "../../src/libraries/StateLibrary.sol";

/// @title Calculate token<>liquidity
/// @notice Helps calculate amounts for bounding fuzz tests
library AmountHelpers {
    function getMaxAmountInForPool(IPoolManager manager, ModifyLiquidityParams memory params, PoolKey memory key)
        public
        view
        returns (uint256 amount0, uint256 amount1)
    {
        PoolId id = key.toId();
        uint128 liquidity = StateLibrary.getLiquidity(manager, id);
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(manager, id);

        uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(params.tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(params.tickUpper);

        amount0 = LiquidityAmounts.getAmount0ForLiquidity(sqrtPriceX96Lower, sqrtPriceX96, liquidity);
        amount1 = LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceX96Upper, sqrtPriceX96, liquidity);
    }
}
