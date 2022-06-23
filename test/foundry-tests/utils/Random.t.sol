pragma solidity ^0.8.13;

import {Test} from 'forge-std/Test.sol';
import {Random} from './Random.sol';
import {TickMath} from '../../../contracts/libraries/TickMath.sol';

contract RandomTest is Test {
    using Random for Random.Rand;

    function testRandomTick(uint256 seed, uint128 salt) external {
        Random.Rand memory rand = Random.Rand(seed, salt);
        int24 spacing = rand.tickSpacing();
        int24 bound = rand.usableTick(spacing);
        assertGe(bound, TickMath.MIN_TICK);
        assertLe(bound, TickMath.MAX_TICK);
    }
}
