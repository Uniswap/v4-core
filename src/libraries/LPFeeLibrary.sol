// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {PoolKey} from "../types/PoolKey.sol";

library LPFeeLibrary {
    using LPFeeLibrary for uint24;

    /// @notice Thrown when the static or dynamic fee on a pool exceeds 100%.
    error FeeTooLarge();

    uint24 public constant FEE_MASK = 0x7FFFFF;
    uint24 public constant OVERRIDE_MASK = 0xBFFFFF;

    // the top bit of the fee is used to signal if a Pool's is dynamic
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000;

    // the second bit of the fee (returned by beforeSwap) is used to signal if the stored fee should be overridden
    uint24 public constant OVERRIDE_FLAG = 0x400000;

    // the lp fee is represented in hundredths of a bip, so the max is 100%
    uint24 public constant MAX_LP_FEE = 1000000;

    function isDynamicFee(uint24 self) internal pure returns (bool) {
        return self & DYNAMIC_FEE_FLAG != 0;
    }

    function isValid(uint24 self) internal pure returns (bool) {
        return self <= MAX_LP_FEE;
    }

    function validate(uint24 self) internal pure {
        if (!self.isValid()) revert FeeTooLarge();
    }

    function getInitialLPFee(uint24 self) internal pure returns (uint24 lpFee) {
        // the initial fee for a dynamic fee pool is 0
        if (self.isDynamicFee()) return 0;
        lpFee = self & FEE_MASK;
        lpFee.validate();
    }

    /// @notice returns true if the fee has the override flag set (top bit of the uint24)
    function isOverride(uint24 self) internal pure returns (bool) {
        return self & OVERRIDE_FLAG != 0;
    }

    /// @notice returns a fee with the override flag removed
    function removeOverrideFlag(uint24 self) internal pure returns (uint24) {
        return self & OVERRIDE_MASK;
    }

    /// @notice Removes the override flag and validates the fee (reverts if the fee is too large)
    function removeOverrideAndValidate(uint24 self) internal pure returns (uint24) {
        uint24 fee = self.removeOverrideFlag();
        fee.validate();
        return fee;
    }
}
