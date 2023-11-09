// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IHooks} from "../interfaces/IHooks.sol";
import {FeeLibrary} from "../libraries/FeeLibrary.sol";

import "forge-std/console2.sol";

/// @notice V4 decides whether to invoke specific hooks by inspecting the leading bits of the address that
/// the hooks contract is deployed to.
/// For example, a hooks contract deployed to address: 0x9000000000000000000000000000000000000000
/// has leading bits '1001' which would cause the 'before initialize' and 'after modify position' hooks to be used.
library Hooks {
    using FeeLibrary for uint24;

    uint256 internal constant BEFORE_INITIALIZE_FLAG = 1 << 159;
    uint256 internal constant AFTER_INITIALIZE_FLAG = 1 << 158;
    uint256 internal constant BEFORE_MODIFY_POSITION_FLAG = 1 << 157;
    uint256 internal constant AFTER_MODIFY_POSITION_FLAG = 1 << 156;
    uint256 internal constant BEFORE_SWAP_FLAG = 1 << 155;
    uint256 internal constant AFTER_SWAP_FLAG = 1 << 154;
    uint256 internal constant BEFORE_DONATE_FLAG = 1 << 153;
    uint256 internal constant AFTER_DONATE_FLAG = 1 << 152;
    uint256 internal constant ACCESS_LOCK_FLAG = 1 << 151;
    uint256 internal constant OVERRIDE_FLAG = 1 << 150;

    bytes4 constant OVERRIDE_SELECTOR = bytes4(keccak256("OVERRIDE_SELECTOR"));

    // todo not necessarily all calls now?
    struct Calls {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeModifyPosition;
        bool afterModifyPosition;
        bool beforeSwap;
        bool afterSwap;
        bool beforeDonate;
        bool afterDonate;
        bool accessLock;
        bool overrideSelector;
    }

    /// @notice Thrown if the address will not lead to the specified hook calls being called
    /// @param hooks The address of the hooks contract
    error HookAddressNotValid(address hooks);

    /// @notice Hook did not return its selector
    error InvalidHookResponse();

    /// @notice Utility function intended to be used in hook constructors to ensure
    /// the deployed hooks address causes the intended hooks to be called
    /// @param calls The hooks that are intended to be called
    /// @dev calls param is memory as the function will be called from constructors
    function validateHookAddress(IHooks self, Calls memory calls) internal pure {
        if (
            calls.beforeInitialize != shouldCallBeforeInitialize(self)
                || calls.afterInitialize != shouldCallAfterInitialize(self)
                || calls.beforeModifyPosition != shouldCallBeforeModifyPosition(self)
                || calls.afterModifyPosition != shouldCallAfterModifyPosition(self)
                || calls.beforeSwap != shouldCallBeforeSwap(self) || calls.afterSwap != shouldCallAfterSwap(self)
                || calls.beforeDonate != shouldCallBeforeDonate(self) || calls.afterDonate != shouldCallAfterDonate(self)
                || calls.accessLock != shouldAccessLock(self) || calls.overrideSelector != shouldAllowOverride(self)
        ) {
            revert HookAddressNotValid(address(self));
        }
    }

    /// @notice Ensures that the hook address includes at least one hook flag or dynamic fees, or is the 0 address
    /// @param hook The hook to verify
    function isValidHookAddress(IHooks hook, uint24 fee) internal pure returns (bool) {
        // If there is no hook contract set, then fee cannot be dynamic and there cannot be a hook fee on swap or withdrawal.
        return address(hook) == address(0)
            ? !fee.isDynamicFee() && !fee.hasHookSwapFee() && !fee.hasHookWithdrawFee()
            : (
                uint160(address(hook)) >= ACCESS_LOCK_FLAG || fee.isDynamicFee() || fee.hasHookSwapFee()
                    || fee.hasHookWithdrawFee()
            );
    }

    function shouldCallBeforeInitialize(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_INITIALIZE_FLAG != 0;
    }

    function shouldCallAfterInitialize(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_INITIALIZE_FLAG != 0;
    }

    function shouldCallBeforeModifyPosition(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_MODIFY_POSITION_FLAG != 0;
    }

    function shouldCallAfterModifyPosition(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_MODIFY_POSITION_FLAG != 0;
    }

    function shouldCallBeforeSwap(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_SWAP_FLAG != 0;
    }

    function shouldCallAfterSwap(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_SWAP_FLAG != 0;
    }

    function shouldCallBeforeDonate(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_DONATE_FLAG != 0;
    }

    function shouldCallAfterDonate(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_DONATE_FLAG != 0;
    }

    function shouldAccessLock(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & ACCESS_LOCK_FLAG != 0;
    }

    function shouldAllowOverride(IHooks self) internal pure returns (bool) {
        return (uint256(uint160(address(self))) & OVERRIDE_FLAG) != 0;
    }
}
