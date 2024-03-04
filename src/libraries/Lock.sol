// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IHooks} from "../interfaces/IHooks.sol";

/// @notice This is a temporary library that allows us to use transient storage (tstore/tload)
/// TODO: This library can be deleted when we have the transient keyword support in solidity.
library Lock {
    // The slot holding the lock, transiently
    uint256 constant LOCK_SLOT = uint256(keccak256("Lock")) - 1;

    function lock() internal {
        uint256 slot = LOCK_SLOT;
        assembly {
            // set the lock
            tstore(slot, true)
        }
    }

    function unlock() internal {
        uint256 slot = LOCK_SLOT;
        assembly {
            tstore(slot, false)
        }
    }

    function isLocked() internal view returns (bool locked) {
        uint256 slot = LOCK_SLOT;
        assembly {
            locked := tload(slot)
        }
    }
}
