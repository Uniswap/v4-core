// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTestHooks} from "./BaseTestHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {Test} from "forge-std/Test.sol";

contract AccessLockHook is BaseTestHooks {
    using CurrencyLibrary for Currency;

    IPoolManager manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    enum LockAction {
        Mint,
        Take,
        Donate,
        Swap,
        ModifyPosition
    }

    function beforeSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata, /* params **/
        bytes calldata hookData
    ) external override returns (bytes4) {
        return _executeAction(key, hookData, IHooks.beforeSwap.selector);
    }

    function beforeDonate(
        address, /* sender **/
        PoolKey calldata key,
        uint256, /* amount0 **/
        uint256, /* amount1 **/
        bytes calldata hookData
    ) external override returns (bytes4) {
        return _executeAction(key, hookData, IHooks.beforeDonate.selector);
    }

    function beforeModifyPosition(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata, /* params **/
        bytes calldata hookData
    ) external override returns (bytes4) {
        return _executeAction(key, hookData, IHooks.beforeModifyPosition.selector);
    }

    function _executeAction(PoolKey memory key, bytes calldata hookData, bytes4 selector) internal returns (bytes4) {
        if (hookData.length == 0) {
            // We have re-entered the hook or we are initializing liquidity in the pool before testing the lock actions.
            return selector;
        }
        (uint256 amount, LockAction action) = abi.decode(hookData, (uint256, LockAction));

        // These actions just use some hardcoded parameters.
        if (action == LockAction.Mint) {
            manager.mint(key.currency1, address(this), amount);
        } else if (action == LockAction.Take) {
            manager.take(key.currency1, address(this), amount);
        } else if (action == LockAction.Donate) {
            manager.donate(key, amount, amount, new bytes(0));
        } else if (action == LockAction.Swap) {
            manager.swap(
                key,
                IPoolManager.SwapParams({
                    zeroForOne: true,
                    amountSpecified: int256(amount),
                    sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1
                }),
                new bytes(0)
            );
        } else if (action == LockAction.ModifyPosition) {
            manager.modifyPosition(
                key,
                IPoolManager.ModifyPositionParams({tickLower: -60, tickUpper: 60, liquidityDelta: int256(amount)}),
                new bytes(0)
            );
        } else {
            revert("Invalid action");
        }

        return selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}

// Hook that can access the lock.
// Also has the ability to call out to another hook or pool.
contract AccessLockHook2 is Test, BaseTestHooks {
    IPoolManager manager;

    error IncorrectHookSet();

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function beforeModifyPosition(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (manager.getCurrentHook() != address(this)) {
            revert IncorrectHookSet();
        }

        (bool shouldCallHook, PoolKey memory key2) = abi.decode(hookData, (bool, PoolKey));

        if (shouldCallHook) {
            // Should revert.
            bytes memory hookData2 = abi.encode(100, AccessLockHook.LockAction.Mint);
            IHooks(key2.hooks).beforeModifyPosition(sender, key, params, hookData2); // params dont really matter, just want to tell the other hook to do a mint action, but will revert
        } else {
            // Should succeed and set current hook to key2.hooks
            manager.modifyPosition(key2, params, new bytes(0));
            if (manager.getCurrentHook() != address(key2.hooks)) {
                revert IncorrectHookSet();
            }
            // Should revert since currentHook is the other pools hook
            manager.mint(key.currency1, address(this), 10);
        }
        return IHooks.beforeModifyPosition.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}
