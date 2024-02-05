// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibString} from "solmate/utils/LibString.sol";

import {console2 as console} from "forge-std/console2.sol";

library FormatLib {
    using LibString for uint256;
    using LibString for int256;

    function logBits256(uint256 x, string memory message) internal pure {
        logBits256(x, message, 16);
    }

    function logBits256(uint256 x, string memory message, uint256 bitsPerRow) internal pure {
        uint256 rows = 256 / bitsPerRow;
        require(rows * bitsPerRow == 256);
        uint256 mask = (1 << bitsPerRow) - 1;
        console.log(message);
        for (uint256 i = rows; i > 0; i--) {
            uint256 offset = i * bitsPerRow - bitsPerRow;
            console.log("  %s", toBin((x >> offset) & mask, bitsPerRow));
        }
    }

    function toBin256(uint256 x) internal pure returns (string memory) {
        return toBin(x, 256);
    }

    function toBin(uint256 x, uint256 bits) internal pure returns (string memory bin) {
        require(bits <= 256);
        /// @solidity memory-safe-assembly
        assembly {
            bin := mload(0x40)
            mstore(bin, bits)
            let endOffset := add(bin, add(bits, 0x20))
            mstore(0x40, endOffset)

            let lastOffset := sub(endOffset, 1)

            for { let i := 0 } lt(i, bits) { i := add(i, 1) } {
                mstore8(sub(lastOffset, i), add(0x30, and(1, shr(i, x))))
            }
        }
    }

    function formatDecimals(int256 value, uint8 decimals) internal pure returns (string memory) {
        return formatDecimals(value, decimals, decimals);
    }

    function formatDecimals(uint256 value, uint8 decimals) internal pure returns (string memory) {
        return formatDecimals(value, decimals, decimals);
    }

    function formatDecimals(int256 value, uint8 decimals, uint8 roundTo) internal pure returns (string memory) {
        int256 one = int256(10 ** decimals);
        assert(one > 0);

        int256 aboveDecimal = abs(value / one);
        int256 belowDecimal = abs(value % one);

        roundTo = roundTo > decimals ? decimals : roundTo;

        int256 roundedUnit = int256(10 ** uint256(decimals - roundTo));
        assert(roundedUnit > 0);

        int256 decimalValue = (belowDecimal + roundedUnit / 2) / roundedUnit;

        string memory decimalRepr = decimalValue.toString();
        while (bytes(decimalRepr).length < roundTo) {
            decimalRepr = string.concat("0", decimalRepr);
        }

        return string.concat(value < 0 ? "-" : "", aboveDecimal.toString(), ".", decimalRepr);
    }

    function formatDecimals(uint256 value, uint8 decimals, uint8 roundTo) internal pure returns (string memory) {
        uint256 one = 10 ** uint256(decimals);
        uint256 aboveDecimal = value / one;
        uint256 belowDecimal = value % one;

        roundTo = roundTo > decimals ? decimals : roundTo;

        uint256 roundedUnit = 10 ** uint256(decimals - roundTo);

        uint256 decimalValue = (belowDecimal + roundedUnit / 2) / roundedUnit;

        string memory decimalRepr = decimalValue.toString();
        while (bytes(decimalRepr).length < roundTo) {
            decimalRepr = string.concat("0", decimalRepr);
        }

        return string.concat(aboveDecimal.toString(), ".", decimalRepr);
    }

    function abs(int256 x) internal pure returns (int256) {
        return x < 0 ? -x : x;
    }
}
