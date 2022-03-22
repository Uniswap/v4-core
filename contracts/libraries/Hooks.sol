// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;
import {IHooks} from '../interfaces/IHooks.sol';

/// @notice V4 decides whether to invoke specific hooks by inspecting the leading bits of the address that
/// the hooks contract is deployed to.
/// For example, a hooks contract deployed to address: 0x9000000000000000000000000000000000000000
/// has leading bits '1001' which would cause the 'before initialize' and 'after swap' hooks to be used.
library Hooks {
    uint256 public constant BEFORE_INITIALIZE_FLAG = 1 << 159;
    uint256 public constant AFTER_INITIALIZE_FLAG = 1 << 158;
    uint256 public constant BEFORE_SWAP_FLAG = 1 << 157;
    uint256 public constant AFTER_SWAP_FLAG = 1 << 156;
    uint256 public constant BEFORE_MODIFY_POSITION_FLAG = 1 << 155;
    uint256 public constant AFTER_MODIFY_POSITION_FLAG = 1 << 154;

    struct Calls {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeModifyPosition;
        bool afterModifyPosition;
        bool beforeSwap;
        bool afterSwap;
    }

    /// @notice Utility function intended to be used in hook constructors to ensure
    /// the deployed hook address will be called
    /// @param calls The hooks that are intended to be called
    /// @dev calls param is memory as the function will be called from constructors
    /// @return True if the hooks address causes only the specified hooks to be invoked
    function isValidHookAddress(IHooks self, Calls memory calls) internal pure returns (bool) {
        if (calls.beforeInitialize != shouldCallBeforeInitialize(self)) {
            return false;
        }
        if (calls.afterInitialize != shouldCallAfterInitialize(self)) {
            return false;
        }
        if (calls.beforeSwap != shouldCallBeforeSwap(self)) {
            return false;
        }
        if (calls.afterSwap != shouldCallAfterSwap(self)) {
            return false;
        }
        if (calls.beforeModifyPosition != shouldCallBeforeModifyPosition(self)) {
            return false;
        }
        if (calls.afterModifyPosition != shouldCallAfterModifyPosition(self)) {
            return false;
        }

        return true;
    }

    function shouldCallBeforeInitialize(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_INITIALIZE_FLAG != 0;
    }

    function shouldCallAfterInitialize(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_INITIALIZE_FLAG != 0;
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
