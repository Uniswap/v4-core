pragma solidity ^0.8.13;

import {DSTest} from '../../foundry/testdata/lib/ds-test/src/test.sol';
import {Cheats} from '../../foundry/testdata/cheats/Cheats.sol';
import {Pool} from '../libraries/Pool.sol';
import {TickMath} from '../libraries/TickMath.sol';

contract PoolTest is DSTest {
    using Pool for Pool.State;

    Cheats vm = Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    Pool.State state;

    function testInitialize(uint160 sqrtPriceX96) external {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO || sqrtPriceX96 >= TickMath.MAX_SQRT_RATIO) {
            vm.expectRevert(TickMath.InvalidSqrtRatio.selector);
            state.initialize(sqrtPriceX96);
        } else {
            state.initialize(sqrtPriceX96);
            assertEq(state.slot0.sqrtPriceX96, sqrtPriceX96);
            assertEq(state.slot0.tick, TickMath.getTickAtSqrtRatio(sqrtPriceX96));
        }
    }
}
