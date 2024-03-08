// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {PoolKey} from "../types/PoolKey.sol";

library SwapFeeLibrary {
    using SwapFeeLibrary for uint24;

    /// @notice Thrown when the static or dynamic fee on a pool is exceeds 100%.
    error FeeTooLarge();

    uint24 public constant STATIC_FEE_MASK = 0x0FFFFF;
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000;

    // the swap fee is represented in hundredths of a bip, so the max is 100%
    uint24 public constant MAX_SWAP_FEE = 1000000;

    function isDynamicFee(uint24 self) internal pure returns (bool) {
        return self & DYNAMIC_FEE_FLAG != 0;
    }

    function validateSwapFee(uint24 self) internal pure {
        if (self >= MAX_SWAP_FEE) revert FeeTooLarge();
    }

    function getStaticFee(uint24 self) internal pure returns (uint24) {
        return self & STATIC_FEE_MASK;
    }
}
