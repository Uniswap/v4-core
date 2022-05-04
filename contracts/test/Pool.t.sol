pragma solidity ^0.8.13;

import {DSTest} from '../../foundry/testdata/lib/ds-test/src/test.sol';
import {Cheats} from '../../foundry/testdata/cheats/Cheats.sol';
import {Pool} from '../libraries/Pool.sol';
import {TickMath} from '../libraries/TickMath.sol';

contract PoolTest is DSTest {
    using Pool for Pool.State;

    Cheats vm = Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    Pool.State state;

    function testInitialize(uint160 sqrtPriceX96) public returns (bool) {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO || sqrtPriceX96 >= TickMath.MAX_SQRT_RATIO) {
            vm.expectRevert(TickMath.InvalidSqrtRatio.selector);
            state.initialize(sqrtPriceX96);
            return false;
        } else {
            state.initialize(sqrtPriceX96);
            assertEq(state.slot0.sqrtPriceX96, sqrtPriceX96);
            assertEq(state.slot0.tick, TickMath.getTickAtSqrtRatio(sqrtPriceX96));
            assertLt(state.slot0.tick, TickMath.MAX_TICK);
            assertGt(state.slot0.tick, TickMath.MIN_TICK);
            return true;
        }
    }

    function testModifyPosition(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tickSpacing
    ) public returns (bool) {
        if (testInitialize(sqrtPriceX96)) {
            if (tickLower >= tickUpper) {
                vm.expectRevert(abi.encodeWithSelector(Pool.TicksMisordered.selector, tickLower, tickUpper));
            } else if (tickLower < TickMath.MIN_TICK) {
                vm.expectRevert(abi.encodeWithSelector(Pool.TickLowerOutOfBounds.selector, tickLower));
            } else if (tickUpper > TickMath.MAX_TICK) {
                vm.expectRevert(abi.encodeWithSelector(Pool.TickUpperOutOfBounds.selector, tickUpper));
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

            return true;
        }
        return false;
    }
}
