pragma solidity ^0.8.13;

library Num {
    function bound(
        uint256 num,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256) {
        return min + (num % (max - min));
    }

    function bound(
        int256 num,
        int256 min,
        int256 max
    ) internal pure returns (int256) {
        return min + abs(num % (max - min));
    }

    function abs(int256 a) internal pure returns (int256) {
        return a > 0 ? a : -a;
    }
}
