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
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Constants} from "../../test/utils/Constants.sol";
import {PoolIdLibrary} from "../types/PoolId.sol";

contract AccessLockHook is Test, BaseTestHooks {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    IPoolManager manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    error InvalidAction();

    enum LockAction {
        Mint,
        Take,
        Donate,
        Swap,
        ModifyPosition,
        Burn,
        Settle,
        Initialize,
        NoOp
    }

    function beforeInitialize(
        address, /* sender **/
        PoolKey calldata key,
        uint160, /* sqrtPriceX96 **/
        bytes calldata hookData
    ) external override returns (bytes4) {
        return _executeAction(key, hookData, IHooks.beforeInitialize.selector);
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
        } else if (action == LockAction.NoOp) {
            assertEq(address(manager.getCurrentHook()), address(this));
            return Hooks.NO_OP_SELECTOR;
        } else if (action == LockAction.Burn) {
            manager.burn(key.currency1, amount);
        } else if (action == LockAction.Settle) {
            manager.take(key.currency1, address(this), amount);
            assertEq(MockERC20(Currency.unwrap(key.currency1)).balanceOf(address(this)), amount);
            assertEq(manager.getLockNonzeroDeltaCount(), 1);
            MockERC20(Currency.unwrap(key.currency1)).transfer(address(manager), amount);
            manager.settle(key.currency1);
            assertEq(manager.getLockNonzeroDeltaCount(), 0);
        } else if (action == LockAction.Initialize) {
            PoolKey memory newKey = PoolKey({
                currency0: key.currency0,
                currency1: key.currency1,
                fee: Constants.FEE_LOW,
                tickSpacing: 60,
                hooks: IHooks(address(0))
            });
            manager.initialize(newKey, Constants.SQRT_RATIO_1_2, new bytes(0));
        } else {
            revert InvalidAction();
        }

        return selector;
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
        if (address(manager.getCurrentHook()) != address(this)) {
            revert IncorrectHookSet();
        }

        (bool shouldCallHook, PoolKey memory key2) = abi.decode(hookData, (bool, PoolKey));

        if (shouldCallHook) {
            // Should revert.
            bytes memory hookData2 = abi.encode(100, AccessLockHook.LockAction.Mint);
            IHooks(key2.hooks).beforeModifyPosition(sender, key, params, hookData2); // params dont really matter, just want to tell the other hook to do a mint action, but will revert
        } else {
            // Should succeed and should NOT set the current hook to key2.hooks.
            // The permissions should remain to THIS hook during this lock.
            manager.modifyPosition(key2, params, new bytes(0));

            if (address(manager.getCurrentHook()) != address(this)) {
                revert IncorrectHookSet();
            }
            // Should succeed.
            manager.mint(key.currency1, address(this), 10);
        }
        return IHooks.beforeModifyPosition.selector;
    }
}

// Reenters the PoolManager to donate and asserts currentHook is set and unset correctly throughout the popping and pushing of locks.
contract AccessLockHook3 is Test, ILockCallback, BaseTestHooks {
    IPoolManager manager;
    // The pool to donate to in the nested lock.
    // Ensure this has balance of currency0.abi
    PoolKey key;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    // Instead of passing through key all the way to the nested lock, just save it.
    function setKey(PoolKey memory _key) external {
        key = _key;
    }

    function beforeModifyPosition(
        address, /* sender **/
        PoolKey calldata, /* key **/
        IPoolManager.ModifyPositionParams calldata, /* params **/
        bytes calldata /* hookData **/
    ) external override returns (bytes4) {
        assertEq(address(manager.getCurrentHook()), address(this));
        manager.lock(address(this), abi.encode(true));
        assertEq(address(manager.getCurrentHook()), address(this));
        manager.lock(address(this), abi.encode(false));
        assertEq(address(manager.getCurrentHook()), address(this));
        return IHooks.beforeModifyPosition.selector;
    }

    function lockAcquired(address caller, bytes memory data) external returns (bytes memory) {
        require(caller == address(this));
        assertEq(manager.getLockLength(), 2);
        assertEq(address(manager.getCurrentHook()), address(0));

        (bool isFirstLock) = abi.decode(data, (bool));
        if (isFirstLock) {
            manager.donate(key, 10, 0, new bytes(0));
            assertEq(address(manager.getCurrentHook()), address(key.hooks));
            MockERC20(Currency.unwrap(key.currency0)).transfer(address(manager), 10);
            manager.settle(key.currency0);
        }
        return data;
    }
}
