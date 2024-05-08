// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BalanceDelta} from "./BalanceDelta.sol";

// Type used only internally to decode the different types of deltas returned by hooks
// For afterAddLiquidity and afterRemoveLiquidity, HookReturnDelta is a BalanceDelta
// For beforeSwap, HookReturnDelta is a BeforeSwapDelta
// For afterSwap, HookReturnDelta is an int128 in the lower 128 bits
type HookReturnDelta is bytes32;

// Return type of the beforeSwap hook.
// Upper 128 bits is the delta in specified tokens. Lower 128 bits is delta in unspecified tokens (to match the afterSwap hook)
type BeforeSwapDelta is int256;

// Creates a BeforeSwapDelta from specified and unspecified
function toBeforeSwapDelta(int128 deltaSpecified, int128 deltaUnspecified)
    pure
    returns (BeforeSwapDelta beforeSwapDelta)
{
    /// @solidity memory-safe-assembly
    assembly {
        beforeSwapDelta := or(shl(128, deltaSpecified), and(0xffffffffffffffffffffffffffffffff, deltaUnspecified))
    }
}

library HookReturnDeltaLibrary {
    HookReturnDelta public constant ZERO_DELTA = HookReturnDelta.wrap(bytes32(0));

    /// converts a HookReturnDelta type to a BalanceDelta type
    /// returned by afterAddLiquidity and afterRemoveLiquidity
    function toBalanceDelta(HookReturnDelta delta) internal pure returns (BalanceDelta balanceDelta) {
        assembly {
            balanceDelta := delta
        }
    }

    /// extracts int128 from the upper 128 bits of the HookReturnDelta
    /// returned by beforeSwap
    function getSpecifiedDelta(HookReturnDelta delta) internal pure returns (int128 deltaSpecified) {
        assembly {
            deltaSpecified := shr(128, delta)
        }
    }

    /// extracts int128 from the lower 128 bits of the HookReturnDelta
    /// returned by beforeSwap and afterSwap
    function getUnspecifiedDelta(HookReturnDelta delta) internal pure returns (int128 deltaUnspecified) {
        /// @solidity memory-safe-assembly
        assembly {
            deltaUnspecified := delta
        }
    }
}
