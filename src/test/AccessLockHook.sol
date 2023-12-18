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
import {BalanceDelta} from "../types/BalanceDelta.sol";

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
        ModifyLiquidity,
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

    function beforeAddLiquidity(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata, /* params **/
        bytes calldata hookData
    ) external override returns (bytes4) {
        return _executeAction(key, hookData, IHooks.beforeAddLiquidity.selector);
    }

    function beforeRemoveLiquidity(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata, /* params **/
        bytes calldata hookData
    ) external override returns (bytes4) {
        return _executeAction(key, hookData, IHooks.beforeRemoveLiquidity.selector);
    }

    function _executeAction(PoolKey memory key, bytes calldata hookData, bytes4 selector) internal returns (bytes4) {
        if (hookData.length == 0) {
            // We have re-entered the hook or we are initializing liquidity in the pool before testing the lock actions.
            return selector;
        }
        (uint256 amount, LockAction action) = abi.decode(hookData, (uint256, LockAction));

        // These actions just use some hardcoded parameters.
        if (action == LockAction.Mint) {
            manager.mint(address(this), key.currency1.toId(), amount);
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
        } else if (action == LockAction.ModifyLiquidity) {
            manager.modifyLiquidity(
                key,
                IPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: int256(amount)}),
                new bytes(0)
            );
        } else if (action == LockAction.NoOp) {
            assertEq(address(manager.getCurrentHook()), address(this));
            return Hooks.NO_OP_SELECTOR;
        } else if (action == LockAction.Burn) {
            manager.burn(address(this), key.currency1.toId(), amount);
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

    using CurrencyLibrary for Currency;

    error IncorrectHookSet();

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (address(manager.getCurrentHook()) != address(this)) {
            revert IncorrectHookSet();
        }

        (bool shouldCallHook, PoolKey memory key2) = abi.decode(hookData, (bool, PoolKey));

        if (shouldCallHook) {
            // Should revert.
            bytes memory hookData2 = abi.encode(100, AccessLockHook.LockAction.Mint);
            IHooks(key2.hooks).beforeAddLiquidity(sender, key, params, hookData2); // params dont really matter, just want to tell the other hook to do a mint action, but will revert
        } else {
            // Should succeed and should NOT set the current hook to key2.hooks.
            // The permissions should remain to THIS hook during this lock.
            manager.modifyLiquidity(key2, params, new bytes(0));

            if (address(manager.getCurrentHook()) != address(this)) {
                revert IncorrectHookSet();
            }
            // Should succeed.
            manager.mint(address(this), key.currency1.toId(), 10);
        }
        return IHooks.beforeAddLiquidity.selector;
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

    function beforeAddLiquidity(
        address, /* sender **/
        PoolKey calldata, /* key **/
        IPoolManager.ModifyLiquidityParams calldata, /* params **/
        bytes calldata /* hookData **/
    ) external override returns (bytes4) {
        assertEq(address(manager.getCurrentHook()), address(this));
        manager.lock(address(this), abi.encode(true));
        assertEq(address(manager.getCurrentHook()), address(this));
        manager.lock(address(this), abi.encode(false));
        assertEq(address(manager.getCurrentHook()), address(this));
        return IHooks.beforeAddLiquidity.selector;
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

contract AccessLockFeeHook is Test, BaseTestHooks {
    IPoolManager manager;

    uint256 constant WITHDRAWAL_FEE_BIPS = 40; // 40/10000 = 0.4%
    uint256 constant SWAP_FEE_BIPS = 55; // 55/10000 = 0.55%
    uint256 constant TOTAL_BIPS = 10000;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function afterAddLiquidity(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata, /* params **/
        BalanceDelta delta,
        bytes calldata /* hookData **/
    ) external override returns (bytes4) {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // positive delta => user owes money => liquidity addition
        assert(amount0 >= 0 && amount1 >= 0);

        return IHooks.afterAddLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata, /* params **/
        BalanceDelta delta,
        bytes calldata /* hookData **/
    ) external override returns (bytes4) {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // negative delta => user is owed money => liquidity withdrawal
        uint256 amount0Fee = uint128(-amount0) * WITHDRAWAL_FEE_BIPS / TOTAL_BIPS;
        uint256 amount1Fee = uint128(-amount1) * WITHDRAWAL_FEE_BIPS / TOTAL_BIPS;

        manager.take(key.currency0, address(this), amount0Fee);
        manager.take(key.currency1, address(this), amount1Fee);

        return IHooks.afterRemoveLiquidity.selector;
    }

    function afterSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata /* hookData **/
    ) external override returns (bytes4) {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // fee on output token - output delta will be negative
        (Currency feeCurrency, uint256 outputAmount) =
            (params.zeroForOne) ? (key.currency1, uint128(-amount1)) : (key.currency0, uint128(-amount0));

        uint256 feeAmount = outputAmount * SWAP_FEE_BIPS / TOTAL_BIPS;

        manager.take(feeCurrency, address(this), feeAmount);

        return IHooks.afterSwap.selector;
    }
}
