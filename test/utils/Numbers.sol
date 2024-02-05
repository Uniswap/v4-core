// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StdUtils} from "forge-std/StdUtils.sol";

/// @author philogy <https://github.com/philogy>
abstract contract Numbers is StdUtils {
    function clampToI128(int256 x) internal pure returns (int128) {
        return int128(clamp(x, type(int128).min, type(int128).max));
    }

    function clamp(int256 x, int256 lower, int256 upper) internal pure returns (int256) {
        if (x < lower) {
            return lower;
        } else if (x > upper) {
            return upper;
        } else {
            return x;
        }
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x > y ? x : y;
    }

    function sanityCheck(bool cond) internal pure {
        assert(cond);
    }
}
