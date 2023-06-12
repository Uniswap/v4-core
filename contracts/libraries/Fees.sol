// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

library Fees {
    uint24 public constant STATIC_FEE_MASK = 0x0FFFFF;
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000; // 1000
    uint24 public constant HOOK_SWAP_FEE_FLAG = 0x400000; // 0100
    uint24 public constant HOOK_WITHDRAW_FEE_FLAG = 0x200000; // 0010

    function isDynamicFee(uint24 self) internal pure returns (bool) {
        return self & DYNAMIC_FEE_FLAG != 0;
    }

    function hasHookSwapFee(uint24 self) internal pure returns (bool) {
        return self & HOOK_SWAP_FEE_FLAG != 0;
    }

    function hasHookWithdrawFee(uint24 self) internal pure returns (bool) {
        return self & HOOK_WITHDRAW_FEE_FLAG != 0;
    }
}
