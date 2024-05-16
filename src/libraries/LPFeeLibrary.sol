// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {PoolKey} from "../types/PoolKey.sol";

library LPFeeLibrary {
    using LPFeeLibrary for uint24;

    /// @notice Thrown when the static or dynamic fee on a pool exceeds 100%.
    error FeeTooLarge();

    uint24 public constant STATIC_FEE_MASK = 0x7FFFFF;
    uint24 public constant DYNAMIC_FEE_FLAG = 0x800000;

    // the lp fee is represented in hundredths of a bip, so the max is 100%
    uint24 public constant MAX_LP_FEE = 1000000;
    uint24 public constant FEE_OVERRIDE_FLAG = 0xF00000;

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
        lpFee = self & STATIC_FEE_MASK;
        lpFee.validate();
    }

    /// @dev converts a fee (returned from beforeSwap) to an override fee by setting the top 4 bits of the uint24
    function asOverrideFee(uint24 self) internal pure returns (uint24 lpFeeOverride) {
        assembly {
            lpFeeOverride := or(self, FEE_OVERRIDE_FLAG)
        }
    }

    /// @dev converts an override fee to a normal uint24 fee
    function getOverride(uint24 lpFeeOverride) internal pure returns (uint24 lpFee) {
        // if (lpFeeOverride && FEE_OVERRIDE_FLAG) == FEE_OVERRIDE_FLAG, mask out the flag
        assembly {
            let result := and(lpFeeOverride, FEE_OVERRIDE_FLAG)
            if eq(result, FEE_OVERRIDE_FLAG) {
                lpFee := and(lpFeeOverride, 0x0FFFFF)
            }
            
            // if lpFeeOverride does not have the flag set, then set the LP fee to the override flag (1+ million)
            // this value exceeds the maximum fee, so it will not be used in Pool.swap
            if iszero(eq(result, FEE_OVERRIDE_FLAG)) {
                lpFee := FEE_OVERRIDE_FLAG
            }
        }
    }
}
