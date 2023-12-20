// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

library FeeLibrary {
    uint24 public constant STATIC_FEE_MASK = 0x0FFFFF;
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000; // 1000

    function isDynamicFee(uint24 self) internal pure returns (bool) {
        return self & DYNAMIC_FEE_FLAG != 0;
    }

    function isStaticFeeTooLarge(uint24 self) internal pure returns (bool) {
        return self & STATIC_FEE_MASK >= 1000000;
    }

    function getStaticFee(uint24 self) internal pure returns (uint24) {
        return self & STATIC_FEE_MASK;
    }
}
