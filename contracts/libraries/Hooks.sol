// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;
import {IHooks} from '../interfaces/IHooks.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

/// @notice V4 decides whether to invoke specific hooks by inspecting the leading bits of the address that
/// the hooks contract is deployed to.
/// For example, a hooks contract deployed to address: 0x9000000000000000000000000000000000000000
/// has leading bits '1001' which would cause the 'before initialize' and 'after swap' hooks to be used.
library Hooks {
    using Hooks for IHooks;

    /// @notice Hook did not return its selector
    error InvalidHookResponse();

    uint256 public constant BEFORE_INITIALIZE_FLAG = 1 << 159;
    uint256 public constant AFTER_INITIALIZE_FLAG = 1 << 158;
    uint256 public constant BEFORE_MODIFY_POSITION_FLAG = 1 << 157;
    uint256 public constant AFTER_MODIFY_POSITION_FLAG = 1 << 156;
    uint256 public constant BEFORE_SWAP_FLAG = 1 << 155;
    uint256 public constant AFTER_SWAP_FLAG = 1 << 154;
    uint256 public constant BEFORE_DONATE_FLAG = 1 << 153;
    uint256 public constant AFTER_DONATE_FLAG = 1 << 152;

    struct Calls {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeModifyPosition;
        bool afterModifyPosition;
        bool beforeSwap;
        bool afterSwap;
        bool beforeDonate;
        bool afterDonate;
    }

    /// @notice Thrown if the address will not lead to the specified hook calls being called
    /// @param hooks The address of the hooks contract
    error HookAddressNotValid(address hooks);

    /// @notice Utility function intended to be used in hook constructors to ensure
    /// the deployed hooks address causes the intended hooks to be called
    /// @param calls The hooks that are intended to be called
    /// @dev calls param is memory as the function will be called from constructors
    function validateHookAddress(IHooks self, Calls memory calls) internal pure {
        if (
            calls.beforeInitialize != shouldCallBeforeInitialize(self) ||
            calls.afterInitialize != shouldCallAfterInitialize(self) ||
            calls.beforeModifyPosition != shouldCallBeforeModifyPosition(self) ||
            calls.afterModifyPosition != shouldCallAfterModifyPosition(self) ||
            calls.beforeSwap != shouldCallBeforeSwap(self) ||
            calls.afterSwap != shouldCallAfterSwap(self) ||
            calls.beforeDonate != shouldCallBeforeDonate(self) ||
            calls.afterDonate != shouldCallAfterDonate(self)
        ) {
            revert HookAddressNotValid(address(self));
        }
    }

    /// @notice Ensures that the hook address includes at least one hook flag, or is the 0 address
    /// @param hook The hook to verify
    function isValidHookAddress(IHooks hook) internal pure returns (bool) {
        return address(hook) == address(0) || uint160(address(hook)) >= uint160(AFTER_DONATE_FLAG);
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

    /// @notice Runs beforeInitialize hook with validation checks
    /// @param self The hook to run
    /// @param sender The address calling initialize
    /// @param key The pool details
    /// @param sqrtPriceX96 Initial pool price
    function safeBeforeInitialize(
        IHooks self,
        address sender,
        IPoolManager.PoolKey memory key,
        uint160 sqrtPriceX96
    ) internal {
        if (
            self.shouldCallBeforeInitialize() &&
            self.beforeInitialize(sender, key, sqrtPriceX96) != IHooks.beforeInitialize.selector
        ) {
            revert InvalidHookResponse();
        }
    }

    
    /// @notice Runs afterInitialize hook with validation checks
    /// @param self The hook to run
    /// @param sender The address calling initialize
    /// @param key The pool details
    /// @param sqrtPriceX96 Initial pool price
    /// @param tick Initial tick
    function safeAfterInitialize(
        IHooks self,
        address sender,
        IPoolManager.PoolKey memory key,
        uint160 sqrtPriceX96,
        int24 tick
    ) internal {
        if (
            self.shouldCallAfterInitialize() &&
                self.afterInitialize(sender, key, sqrtPriceX96, tick) != IHooks.afterInitialize.selector
        ) {
            revert InvalidHookResponse();
        }
    }

    /// @notice Runs beforeModifyPosition hook with validation checks
    /// @param self The hook to run
    /// @param sender The address calling initialize
    /// @param key The pool details
    /// @param params The modify position params
    function safeBeforeModifyPosition(
        IHooks self,
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params
    ) internal {
        if (
            self.shouldCallBeforeModifyPosition() &&
                self.beforeModifyPosition(sender, key, params) != IHooks.beforeModifyPosition.selector
        ) {
            revert InvalidHookResponse();
        }
    }

    /// @notice Runs afterModifyPosition hook with validation checks
    /// @param self The hook to run
    /// @param sender The address calling initialize
    /// @param key The pool details
    /// @param params The modify position params
    /// @param delta Change in balance after the position modification
    function safeAfterModifyPosition(
        IHooks self,
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params,
        IPoolManager.BalanceDelta memory delta
    ) internal {
        if (
            self.shouldCallAfterModifyPosition() &&
                self.afterModifyPosition(sender, key, params, delta) != IHooks.afterModifyPosition.selector
        ) {
            revert InvalidHookResponse();
        }
    }

    /// @notice Runs beforeSwap hook with validation checks
    /// @param self The hook to run
    /// @param sender The address calling initialize
    /// @param key The pool details
    /// @param params The swap params
    function safeBeforeSwap(
        IHooks self,
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.SwapParams memory params
    ) internal {
        if (self.shouldCallBeforeSwap() && self.beforeSwap(sender, key, params) != IHooks.beforeSwap.selector) {
            revert InvalidHookResponse();
        }
    }

    /// @notice Runs afterSwap hook with validation checks
    /// @param self The hook to run
    /// @param sender The address calling initialize
    /// @param key The pool details
    /// @param params The swap params
    /// @param delta Change in balance after the swap
    function safeAfterSwap(
        IHooks self,
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.SwapParams memory params,
        IPoolManager.BalanceDelta memory delta
    ) internal {
        if (self.shouldCallAfterSwap() && self.afterSwap(sender, key, params, delta) != IHooks.afterSwap.selector) {
            revert InvalidHookResponse();
        }
    }

    /// @notice Runs beforeDonate hook with validation checks
    /// @param self The hook to run
    /// @param sender The address calling initialize
    /// @param key The pool details
    /// @param amount0 Amount of token0 donated
    /// @param amount1 Amount of token1 donated
    function safeBeforeDonate(
        IHooks self,
        address sender,
        IPoolManager.PoolKey memory key,
        uint256 amount0,
        uint256 amount1
    ) internal {
        if (
            self.shouldCallBeforeDonate() &&
                self.beforeDonate(sender, key, amount0, amount1) != IHooks.beforeDonate.selector
        ) {
            revert InvalidHookResponse();
        }
    }

    /// @notice Runs afterDonate hook with validation checks
    /// @param self The hook to run
    /// @param sender The address calling initialize
    /// @param key The pool details
    /// @param amount0 Amount of token0 donated
    /// @param amount1 Amount of token1 donated
    function safeAfterDonate(
        IHooks self,
        address sender,
        IPoolManager.PoolKey memory key,
        uint256 amount0,
        uint256 amount1
    ) internal {
        if (
            self.shouldCallAfterDonate() &&
                self.afterDonate(sender, key, amount0, amount1) != IHooks.afterDonate.selector
        ) {
            revert InvalidHookResponse();
        }
    }
}
