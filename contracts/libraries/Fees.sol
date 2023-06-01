// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Fees {
    uint24 public constant MASK = 0x0FFFFF;
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000; // 1000
    uint24 public constant HOOK_FEE_FLAG = 0x400000; // 0100

    function isDynamicFee(uint24 self) internal pure returns (bool) {
        return self & DYNAMIC_FEE_FLAG != 0;
    }

    function hasHookEnabledFee(uint24 self) internal pure returns (bool) {
        return self & HOOK_FEE_FLAG != 0;
    }
}
