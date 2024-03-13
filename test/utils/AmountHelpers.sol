// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {PoolManager} from "../../src/PoolManager.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";

/// @title Calculate token<>liquidity
/// @notice Helps calculate amounts for bounding fuzz tests
library AmountHelpers {
    function getMaxAmountInForPool(
        PoolManager manager,
        IPoolManager.ModifyLiquidityParams memory params,
        PoolKey memory key
    ) public view returns (uint256 amount0, uint256 amount1) {
        PoolId id = PoolIdLibrary.toId(key);
        uint128 liquidity = manager.getLiquidity(id);
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(id);

        uint160 sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(params.tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(params.tickUpper);

        amount0 = LiquidityAmounts.getAmount0ForLiquidity(sqrtPriceX96Lower, sqrtPriceX96, liquidity);
        amount1 = LiquidityAmounts.getAmount0ForLiquidity(sqrtPriceX96Upper, sqrtPriceX96, liquidity);
    }
}
