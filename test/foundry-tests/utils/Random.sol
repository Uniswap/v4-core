pragma solidity ^0.8.13;

import {TickMath} from '../../../contracts/libraries/TickMath.sol';
import {Num} from './Num.sol';

/// @notice function for generating pseudorandom numbers of various types from seeds
///  Useful for creating scenario tests using foundry fuzzed seeds
library Random {
    using Random for Rand;

    struct Rand {
        uint256 seed;
        uint256 salt;
    }

    function u256(Rand memory self) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(self.seed, ++self.salt)));
    }

    function i256(Rand memory self) internal pure returns (int256) {
        uint256 num = self.u256();
        if (self.boolean()) {
            return -int256(num);
        } else {
            return int256(num);
        }
    }

    function boolean(Rand memory self) internal pure returns (bool) {
        return self.u256() % 2 == 0;
    }

    function tick(Rand memory self, int24 spacing) internal pure returns (int24) {
        int24 num = int24(Num.bound(self.i256(), TickMath.MIN_TICK, TickMath.MAX_TICK));
        if (num % spacing != 0) num -= num % spacing;

        return num;
    }

    function tickSpacing(Rand memory self) internal pure returns (int24) {
        int24 spacing = int24(self.i256());
        if (spacing < 0) {
            spacing -= type(int24).min;
        }
        return (spacing % (2**15 - 1)) + 1;
    }

    function sqrtPrice(Rand memory self) internal pure returns (uint160) {
        return uint160(Num.bound(self.u256(), TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO));
    }
}
