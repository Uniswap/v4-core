// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IHooks} from "../interfaces/IHooks.sol";
import {FeeLibrary} from "../libraries/FeeLibrary.sol";

/// @notice V4 decides whether to invoke specific hooks by inspecting the leading bits of the address that
/// the hooks contract is deployed to.
/// For example, a hooks contract deployed to address: 0x9000000000000000000000000000000000000000
/// has leading bits '1001' which would cause the 'before initialize' and 'after add liquidity' hooks to be used.
library Hooks {
    using FeeLibrary for uint24;

    uint256 internal constant BEFORE_INITIALIZE_FLAG = 1 << 159;
    uint256 internal constant AFTER_INITIALIZE_FLAG = 1 << 158;
    uint256 internal constant BEFORE_ADD_LIQUIDITY_FLAG = 1 << 157;
    uint256 internal constant AFTER_ADD_LIQUIDITY_FLAG = 1 << 156;
    uint256 internal constant BEFORE_REMOVE_LIQUIDITY_FLAG = 1 << 155;
    uint256 internal constant AFTER_REMOVE_LIQUIDITY_FLAG = 1 << 154;
    uint256 internal constant BEFORE_SWAP_FLAG = 1 << 153;
    uint256 internal constant AFTER_SWAP_FLAG = 1 << 152;
    uint256 internal constant BEFORE_DONATE_FLAG = 1 << 151;
    uint256 internal constant AFTER_DONATE_FLAG = 1 << 150;
    uint256 internal constant NO_OP_FLAG = 1 << 149;
    uint256 internal constant ACCESS_LOCK_FLAG = 1 << 148;

    bytes4 public constant NO_OP_SELECTOR = bytes4(keccak256(abi.encodePacked("NoOp")));

    struct Permissions {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeAddLiquidity;
        bool afterAddLiquidity;
        bool beforeRemoveLiquidity;
        bool afterRemoveLiquidity;
        bool beforeSwap;
        bool afterSwap;
        bool beforeDonate;
        bool afterDonate;
        bool noOp;
        bool accessLock;
    }

    /// @notice Thrown if the address will not lead to the specified hook calls being called
    /// @param hooks The address of the hooks contract
    error HookAddressNotValid(address hooks);

    /// @notice Hook did not return its selector
    error InvalidHookResponse();

    /// @notice Utility function intended to be used in hook constructors to ensure
    /// the deployed hooks address causes the intended hooks to be called
    /// @param permissions The hooks that are intended to be called
    /// @dev permissions param is memory as the function will be called from constructors
    function validateHookPermissions(IHooks self, Permissions memory permissions) internal pure {
        if (
            permissions.beforeInitialize != shouldCallBeforeInitialize(self)
                || permissions.afterInitialize != shouldCallAfterInitialize(self)
                || permissions.beforeAddLiquidity != shouldCallBeforeAddLiquidity(self)
                || permissions.afterAddLiquidity != shouldCallAfterAddLiquidity(self)
                || permissions.beforeRemoveLiquidity != shouldCallBeforeRemoveLiquidity(self)
                || permissions.afterRemoveLiquidity != shouldCallAfterRemoveLiquidity(self)
                || permissions.beforeSwap != shouldCallBeforeSwap(self)
                || permissions.afterSwap != shouldCallAfterSwap(self)
                || permissions.beforeDonate != shouldCallBeforeDonate(self)
                || permissions.afterDonate != shouldCallAfterDonate(self) || permissions.noOp != hasPermissionToNoOp(self)
                || permissions.accessLock != hasPermissionToAccessLock(self)
        ) {
            revert HookAddressNotValid(address(self));
        }
    }

    /// @notice Ensures that the hook address includes at least one hook flag or dynamic fees, or is the 0 address
    /// @param hook The hook to verify
    function isValidHookAddress(IHooks hook, uint24 fee) internal pure returns (bool) {
        // if NoOp is allowed, at least one of beforeRemoveLiquidity, beforeAddLiquidity, beforeSwap and beforeDonate should be allowed
        if (
            hasPermissionToNoOp(hook) && !shouldCallBeforeAddLiquidity(hook) && !shouldCallBeforeRemoveLiquidity(hook)
                && !shouldCallBeforeSwap(hook) && !shouldCallBeforeDonate(hook)
        ) {
            return false;
        }
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

    function shouldCallBeforeAddLiquidity(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_ADD_LIQUIDITY_FLAG != 0;
    }

    function shouldCallAfterAddLiquidity(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_ADD_LIQUIDITY_FLAG != 0;
    }

    function shouldCallBeforeRemoveLiquidity(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_REMOVE_LIQUIDITY_FLAG != 0;
    }

    function shouldCallAfterRemoveLiquidity(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_REMOVE_LIQUIDITY_FLAG != 0;
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

    function hasPermissionToAccessLock(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & ACCESS_LOCK_FLAG != 0;
    }

    function hasPermissionToNoOp(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & NO_OP_FLAG != 0;
    }

    function isValidNoOpCall(IHooks self, bytes4 selector) internal pure returns (bool) {
        return hasPermissionToNoOp(self) && selector == NO_OP_SELECTOR;
    }
}
