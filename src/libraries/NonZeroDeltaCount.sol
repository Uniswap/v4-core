// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IHooks} from "../interfaces/IHooks.sol";

/// @notice This is a temporary library that allows us to use transient storage (tstore/tload)
/// for the nonzero delta count.
/// TODO: This library can be deleted when we have the transient keyword support in solidity.
library NonZeroDeltaCount {
    // The slot holding the number of nonzero deltas. bytes32(uint256(keccak256("NonzeroDeltaCount")) - 1)
    bytes32 constant NONZERO_DELTA_COUNT_SLOT = 0x7d4b3164c6e45b97e7d87b7125a44c5828d005af88f9d751cfd78729c5d99a0b;

    function read() internal view returns (uint256 count) {
        assembly {
            count := tload(NONZERO_DELTA_COUNT_SLOT)
        }
    }

    function increment() internal {
        assembly {
            let count := tload(NONZERO_DELTA_COUNT_SLOT)
            count := add(count, 1)
            tstore(NONZERO_DELTA_COUNT_SLOT, count)
        }
    }

    /// @notice Potential to underflow.
    /// Current usage ensures this will not happen because we call decrement with known boundaries (only up to the number of times we call increment).
    function decrement() internal {
        assembly {
            let count := tload(NONZERO_DELTA_COUNT_SLOT)
            count := sub(count, 1)
            tstore(NONZERO_DELTA_COUNT_SLOT, count)
        }
    }
}
