// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Pool} from "../../contracts/libraries/Pool.sol";
import {Deployers} from "./utils/Deployers.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {Position} from "../../contracts/libraries/Position.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";

contract PoolTest is Test, Deployers {
    using Pool for Pool.State;

    Pool.State state;

    function testInitialize(uint160 sqrtPriceX96, uint8 protocolFee) public {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO || sqrtPriceX96 >= TickMath.MAX_SQRT_RATIO) {
            vm.expectRevert(TickMath.InvalidSqrtRatio.selector);
            state.initialize(sqrtPriceX96, protocolFee);
        } else {
            state.initialize(sqrtPriceX96, protocolFee);
            assertEq(state.slot0.sqrtPriceX96, sqrtPriceX96);
            assertEq(state.slot0.protocolFee, protocolFee);
            assertEq(state.slot0.tick, TickMath.getTickAtSqrtRatio(sqrtPriceX96));
            assertLt(state.slot0.tick, TickMath.MAX_TICK);
            assertGt(state.slot0.tick, TickMath.MIN_TICK - 1);
        }
    }

    function boundTickSpacing(int24 unbound) private pure returns (int24) {
        int24 tickSpacing = unbound;
        if (tickSpacing < 0) {
            tickSpacing -= type(int24).min;
        }
        return (tickSpacing % 32767) + 1;
    }

    function testBoundTickSpacing(int24 tickSpacing) external {
        int24 bound = boundTickSpacing(tickSpacing);
        assertGt(bound, 0);
        assertLt(bound, 32768);
    }

    function testModifyPosition(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tickSpacing
    ) public {
        tickSpacing = boundTickSpacing(tickSpacing);

        testInitialize(sqrtPriceX96, 0);

        if (tickLower >= tickUpper) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TicksMisordered.selector, tickLower, tickUpper));
        } else if (tickLower < TickMath.MIN_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickLowerOutOfBounds.selector, tickLower));
        } else if (tickUpper > TickMath.MAX_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickUpperOutOfBounds.selector, tickUpper));
        } else if (liquidityDelta < 0) {
            vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        } else if (liquidityDelta == 0) {
            vm.expectRevert(Position.CannotUpdateEmptyPosition.selector);
        } else if (liquidityDelta > int128(Pool.tickSpacingToMaxLiquidityPerTick(tickSpacing))) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickLiquidityOverflow.selector, tickLower));
        } else if (tickLower % tickSpacing != 0 || tickUpper % tickSpacing != 0) {
            vm.expectRevert();
        }

        state.modifyPosition(
            Pool.ModifyPositionParams({
                owner: address(this),
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                tickSpacing: tickSpacing
            })
        );
    }

    function testLastUpdateTimestamp() public {
        vm.warp(100);
        state.initialize(TickMath.MIN_SQRT_RATIO, 0);
        assertEq(state.slot0.lastSwapTimestamp, 0);

        vm.warp(500);
        state.swap(Pool.SwapParams(300, 20, false, 1, SQRT_RATIO_1_1 + 1));
        assertEq(state.slot0.lastSwapTimestamp, 500);

        vm.warp(700);
        state.swap(Pool.SwapParams(300, 20, false, 1, SQRT_RATIO_1_1 + 2));
        assertEq(state.slot0.lastSwapTimestamp, 700);
    }
}
