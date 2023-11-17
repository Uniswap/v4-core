// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// TODO: Remove this library once the `transient` keyword is supported in solidity.
library CurrentHookAddress {
    uint256 constant HOOK_ADDRESS_SLOT = uint256(keccak256("HookAddress")) - 1;

    function get() internal view returns (address _address) {
        uint256 slot = HOOK_ADDRESS_SLOT;
        assembly {
            _address := tload(slot)
        }
    }

    function set(address _address) internal {
        if (_address != get()) {
            uint256 slot = HOOK_ADDRESS_SLOT;
            assembly {
                tstore(slot, _address)
            }
        }
    }
}
