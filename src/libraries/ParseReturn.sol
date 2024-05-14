// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

library ParseReturn {
    function parseFee(bytes memory result) internal pure returns (uint24 lpFee) {
        // equivalent: (,, lpFee) = abi.decode(result, (bytes4, int256, uint24));
        assembly {
            lpFee := mload(add(result, 0x60))
        }
    }

    function parseReturnDelta(bytes memory result) internal pure returns (int256 hookReturn) {
        // equivalent: (, hookReturn, ) = abi.decode(result, (bytes4, int256, uint24));
        assembly {
            hookReturn := mload(add(result, 0x40))
        }
    }
}
