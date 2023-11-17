// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {FeeLibrary} from "../libraries/FeeLibrary.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";

/// @notice V4 decides whether to invoke specific hooks by inspecting the leading bits of the address that
/// the hooks contract is deployed to.
/// For example, a hooks contract deployed to address: 0x9000000000000000000000000000000000000000
/// has leading bits '1001' which would cause the 'before initialize' and 'after modify position' hooks to be used.
library Hooks {
    using FeeLibrary for uint24;
    using Hooks for IHooks;

    uint256 internal constant BEFORE_INITIALIZE_FLAG = 1 << 159;
    uint256 internal constant AFTER_INITIALIZE_FLAG = 1 << 158;
    uint256 internal constant BEFORE_MODIFY_POSITION_FLAG = 1 << 157;
    uint256 internal constant AFTER_MODIFY_POSITION_FLAG = 1 << 156;
    uint256 internal constant BEFORE_SWAP_FLAG = 1 << 155;
    uint256 internal constant AFTER_SWAP_FLAG = 1 << 154;
    uint256 internal constant BEFORE_DONATE_FLAG = 1 << 153;
    uint256 internal constant AFTER_DONATE_FLAG = 1 << 152;

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

    /// @notice Hook did not return its selector
    error InvalidHookResponse();

    /// @notice Utility function intended to be used in hook constructors to ensure
    /// the deployed hooks address causes the intended hooks to be called
    /// @param calls The hooks that are intended to be called
    /// @dev calls param is memory as the function will be called from constructors
    function validateHookAddress(IHooks self, Calls memory calls) internal pure {
        if (
            calls.beforeInitialize != self.shouldCall(BEFORE_INITIALIZE_FLAG)
                || calls.afterInitialize != self.shouldCall(AFTER_INITIALIZE_FLAG)
                || calls.beforeModifyPosition != self.shouldCall(BEFORE_MODIFY_POSITION_FLAG)
                || calls.afterModifyPosition != self.shouldCall(AFTER_MODIFY_POSITION_FLAG)
                || calls.beforeSwap != self.shouldCall(BEFORE_SWAP_FLAG)
                || calls.afterSwap != self.shouldCall(AFTER_SWAP_FLAG)
                || calls.beforeDonate != self.shouldCall(BEFORE_DONATE_FLAG)
                || calls.afterDonate != self.shouldCall(AFTER_DONATE_FLAG)
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
                uint160(address(hook)) >= AFTER_DONATE_FLAG || fee.isDynamicFee() || fee.hasHookSwapFee()
                    || fee.hasHookWithdrawFee()
            );
    }

    function validateHooksResponse(bytes4 selector, bytes4 expectedSelector) internal pure {
        if (selector != expectedSelector) {
            revert InvalidHookResponse();
        }
    }

    function shouldCall(IHooks self, uint256 call) internal pure returns (bool) {
        return uint256(uint160(address(self))) & call != 0;
    }

    function beforeInitialize(PoolKey memory key, uint160 sqrtPriceX96, bytes memory hookData) internal {
        if (!shouldCall(key.hooks, BEFORE_INITIALIZE_FLAG)) return;
        validateHooksResponse(
            key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96, hookData), IHooks.beforeInitialize.selector
        );
    }

    function afterInitialize(PoolKey memory key, uint160 sqrtPriceX96, int24 tick, bytes memory hookData) internal {
        if (!shouldCall(key.hooks, AFTER_INITIALIZE_FLAG)) return;
        validateHooksResponse(
            key.hooks.afterInitialize(msg.sender, key, sqrtPriceX96, tick, hookData), IHooks.afterInitialize.selector
        );
    }

    function beforeModifyPosition(
        PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params,
        bytes memory hookData
    ) internal {
        if (!key.hooks.shouldCall(BEFORE_MODIFY_POSITION_FLAG)) return;
        validateHooksResponse(
            key.hooks.beforeModifyPosition(msg.sender, key, params, hookData), IHooks.beforeModifyPosition.selector
        );
    }

    function afterModifyPosition(
        PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params,
        BalanceDelta delta,
        bytes memory hookData
    ) internal {
        if (!key.hooks.shouldCall(AFTER_MODIFY_POSITION_FLAG)) return;
        validateHooksResponse(
            key.hooks.afterModifyPosition(msg.sender, key, params, delta, hookData), IHooks.afterModifyPosition.selector
        );
    }

    function beforeSwap(PoolKey memory key, IPoolManager.SwapParams memory params, bytes memory hookData) internal {
        if (!key.hooks.shouldCall(BEFORE_SWAP_FLAG)) return;
        validateHooksResponse(key.hooks.beforeSwap(msg.sender, key, params, hookData), IHooks.beforeSwap.selector);
    }

    function afterSwap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        BalanceDelta delta,
        bytes memory hookData
    ) internal {
        if (!key.hooks.shouldCall(AFTER_SWAP_FLAG)) return;
        validateHooksResponse(key.hooks.afterSwap(msg.sender, key, params, delta, hookData), IHooks.afterSwap.selector);
    }

    function beforeDonate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData) internal {
        if (!key.hooks.shouldCall(BEFORE_DONATE_FLAG)) return;
        validateHooksResponse(
            key.hooks.beforeDonate(msg.sender, key, amount0, amount1, hookData), IHooks.beforeDonate.selector
        );
    }

    function afterDonate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData) internal {
        if (!key.hooks.shouldCall(AFTER_DONATE_FLAG)) return;
        validateHooksResponse(
            key.hooks.afterDonate(msg.sender, key, amount0, amount1, hookData), IHooks.afterDonate.selector
        );
    }
}
