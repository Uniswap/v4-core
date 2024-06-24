// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BalanceDeltas} from "./BalanceDeltas.sol";

// Return type of the beforeSwap hook.
// Upper 128 bits is the delta in specified tokens. Lower 128 bits is delta in unspecified tokens (to match the afterSwap hook)
type BeforeSwapDeltas is int256;

// Creates a BeforeSwapDeltas from specified and unspecified
function toBeforeSwapDeltas(int128 deltaSpecified, int128 deltaUnspecified)
    pure
    returns (BeforeSwapDeltas beforeSwapDeltas)
{
    assembly ("memory-safe") {
        beforeSwapDeltas := or(shl(128, deltaSpecified), and(sub(shl(128, 1), 1), deltaUnspecified))
    }
}

library BeforeSwapDeltasLibrary {
    BeforeSwapDeltas public constant ZERO_DELTAS = BeforeSwapDeltas.wrap(0);

    /// extracts int128 from the upper 128 bits of the BeforeSwapDeltas
    /// returned by beforeSwap
    function getSpecifiedDelta(BeforeSwapDeltas delta) internal pure returns (int128 deltaSpecified) {
        assembly {
            deltaSpecified := sar(128, delta)
        }
    }

    /// extracts int128 from the lower 128 bits of the BeforeSwapDeltas
    /// returned by beforeSwap and afterSwap
    function getUnspecifiedDelta(BeforeSwapDeltas delta) internal pure returns (int128 deltaUnspecified) {
        assembly ("memory-safe") {
            deltaUnspecified := signextend(15, delta)
        }
    }
}
