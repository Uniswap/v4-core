// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IHooks} from "../interfaces/IHooks.sol";

/// @notice This is a temporary library that allows us to use transient storage (tstore/tload)
/// for the nonzero delta count.
/// TODO: This library can be deleted when we have the transient keyword support in solidity.
library NonZeroDeltaCount {
    // The slot holding the number of nonzero deltas.
    uint256 constant NONZERO_DELTA_COUNT = uint256(keccak256("NonzeroDeltaCount")) - 1;

    function read() internal view returns (uint256 count) {
        uint256 slot = NONZERO_DELTA_COUNT;
        assembly {
            count := tload(slot)
        }
    }

    function increment() internal {
        uint256 slot = NONZERO_DELTA_COUNT;
        assembly {
            let count := tload(slot)
            count := add(count, 1)
            tstore(slot, count)
        }
    }

    /// @notice Potential to underflow.
    /// Current usage ensures this will not happen because we call decrement with known boundaries (only up to the number of times we call increment).
    function decrement() internal {
        uint256 slot = NONZERO_DELTA_COUNT;
        assembly {
            let count := tload(slot)
            count := sub(count, 1)
            tstore(slot, count)
        }
    }
}
