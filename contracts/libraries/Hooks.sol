// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;
import {IHooks} from '../interfaces/IHooks.sol';

/// @notice V4 decides whether to invoke specific hooks by inspecting the leading bits of the address that
/// the hooks contract is deployed to.
/// For example, a hooks contract deployed to address: 0x9000000000000000000000000000000000000000
/// has leading bits '1001' which would cause the 'before swap' and 'after modify position' hooks to be used.
library Hooks {
    uint256 public constant BEFORE_SWAP_FLAG = 1 << 159;
    uint256 public constant AFTER_SWAP_FLAG = 1 << 158;
    uint256 public constant BEFORE_MODIFY_POSITION_FLAG = 1 << 157;
    uint256 public constant AFTER_MODIFY_POSITION_FLAG = 1 << 156;
    uint256 public constant HOOK_MASK =
        BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG | BEFORE_MODIFY_POSITION_FLAG | AFTER_MODIFY_POSITION_FLAG;

    struct Calls {
        bool beforeModifyPosition;
        bool afterModifyPosition;
        bool beforeSwap;
        bool afterSwap;
    }

    /// @notice Utility function intended to be used in hook constructors to ensure
    /// the deployed hook address will be called
    /// @param params The hooks that are intended to be called
    /// @return True if the hooks address causes only the specified hooks to be invoked
    function isValidHookAddress(IHooks self, Calls calldata params) internal pure returns (bool) {
        uint256 mask = 0;
        if (params.beforeSwap) {
            mask = mask | BEFORE_SWAP_FLAG;
        }
        if (params.afterSwap) {
            mask = mask | AFTER_SWAP_FLAG;
        }
        if (params.beforeModifyPosition) {
            mask = mask | BEFORE_MODIFY_POSITION_FLAG;
        }
        if (params.afterModifyPosition) {
            mask = mask | AFTER_MODIFY_POSITION_FLAG;
        }

        return uint256(uint160(address(self))) & HOOK_MASK == mask;
    }

    function shouldCallBeforeSwap(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_SWAP_FLAG != 0;
    }

    function shouldCallAfterSwap(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_SWAP_FLAG != 0;
    }

    function shouldCallBeforeModifyPosition(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_MODIFY_POSITION_FLAG != 0;
    }

    function shouldCallAfterModifyPosition(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_MODIFY_POSITION_FLAG != 0;
    }
}
