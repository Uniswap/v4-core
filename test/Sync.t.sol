// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Deployers} from "./utils/Deployers.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Currency} from "../src/types/Currency.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {IUnlockCallback} from "../src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {ActionsRouter, Actions} from "../src/test/ActionsRouter.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";
import {CurrencyReserves} from "../src/libraries/CurrencyReserves.sol";
import {StateLibrary} from "../src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "../src/libraries/TransientStateLibrary.sol";
import {NativeERC20} from "../src/test/NativeERC20.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";

contract SyncTest is Test, Deployers, GasSnapshot {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    // PoolManager has no balance of currency2.
    Currency currency2;
    ActionsRouter router;

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
        currency2 = deployMintAndApproveCurrency();
        router = new ActionsRouter(manager);
    }

    function test_sync_balanceIsZero() public noIsolate {
        assertEq(currency2.balanceOf(address(manager)), uint256(0));
        manager.sync(currency2);
        uint256 balance = currency2.balanceOf(address(manager));

        assertEq(uint256(balance), 0);
        assertEq(manager.getSyncedReserves(), 0);
    }

    function test_sync_balanceIsNonZero() public noIsolate {
        uint256 currency0Balance = currency0.balanceOf(address(manager));
        assertGt(currency0Balance, uint256(0));

        // Without calling sync, getReserves should return 0.
        assertEq(manager.getSyncedReserves(), 0);

        manager.sync(currency0);
        uint256 balance = currency0.balanceOf(address(manager));
        assertEq(balance, currency0Balance, "balance not equal");
        assertEq(manager.getSyncedReserves(), balance);
    }

    function test_settle_withStartingBalance() public noIsolate {
        assertGt(currency0.balanceOf(address(manager)), uint256(0));

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        // Sync has not been called.
        assertEq(manager.getSyncedReserves(), 0);

        swapRouter.swap(key, SWAP_PARAMS, testSettings, new bytes(0));
        (uint256 balanceCurrency0) = currency0.balanceOf(address(manager));
        manager.sync(currency0);
        assertEq(manager.getSyncedReserves(), balanceCurrency0); // Reserves are up to date since settle + sync was called.
    }

    function test_settle_withNoStartingBalance() public noIsolate {
        assertEq(currency2.balanceOf(address(manager)), uint256(0));

        (Currency cur0, Currency cur1) = currency0 < currency2 ? (currency0, currency2) : (currency2, currency0);
        PoolKey memory key2 =
            PoolKey({currency0: cur0, currency1: cur1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});

        manager.initialize(key2, SQRT_PRICE_1_1, new bytes(0));

        // Sync has not been called.
        assertEq(manager.getSyncedReserves(), 0);
        modifyLiquidityRouter.modifyLiquidity(key2, IPoolManager.ModifyLiquidityParams(-60, 60, 100, 0), new bytes(0));
        (uint256 balanceCurrency2) = currency2.balanceOf(address(manager));
        manager.sync(currency2);
        assertEq(manager.getSyncedReserves(), balanceCurrency2);
    }

    function test_settle_payOnBehalf(address taker, uint256 amount) public {
        vm.assume(taker != address(router));
        amount = bound(amount, 1, uint256(int256(type(int128).max)));
        MockERC20(Currency.unwrap(currency2)).approve(address(router), type(uint256).max);
        MockERC20(Currency.unwrap(currency2)).mint(address(manager), amount);

        Actions[] memory actions = new Actions[](6);
        bytes[] memory params = new bytes[](6);

        actions[0] = Actions.PRANK_TAKE_FROM;
        params[0] = abi.encode(currency2, taker, taker, amount);

        actions[1] = Actions.ASSERT_DELTA_EQUALS;
        params[1] = abi.encode(currency2, taker, int256(amount) * -1);

        actions[2] = Actions.SYNC;
        params[2] = abi.encode(currency2);

        actions[3] = Actions.TRANSFER_FROM;
        params[3] = abi.encode(currency2, address(this), address(manager), amount);

        actions[4] = Actions.SETTLE_FOR;
        params[4] = abi.encode(taker);

        actions[5] = Actions.ASSERT_DELTA_EQUALS;
        params[5] = abi.encode(currency2, taker, 0);

        router.executeActions(actions, params);
    }

    /// @notice When there is no balance and reserves are set to 0, no delta should be applied.
    function test_settle_noBalanceInPool_shouldNotApplyDelta() public noIsolate {
        assertEq(currency2.balanceOf(address(manager)), uint256(0));

        manager.sync(currency2);
        assertEq(manager.getSyncedReserves(), 0);

        Actions[] memory actions = new Actions[](2);
        bytes[] memory params = new bytes[](2);

        actions[0] = Actions.SETTLE;

        actions[1] = Actions.ASSERT_DELTA_EQUALS;
        params[1] = abi.encode(currency2, address(router), 0);

        router.executeActions(actions, params);
    }

    /// @notice When there is a balance, no delta should be applied.
    function test_settle_balanceInPool_shouldNotApplyDelta() public noIsolate {
        uint256 currency0Balance = currency0.balanceOf(address(manager));

        // Sync has not been called.
        assertEq(manager.getSyncedReserves(), 0);

        manager.sync(currency0);
        assertEq(manager.getSyncedReserves(), currency0Balance);

        Actions[] memory actions = new Actions[](2);
        bytes[] memory params = new bytes[](2);

        actions[0] = Actions.SETTLE;

        actions[1] = Actions.ASSERT_DELTA_EQUALS;
        params[1] = abi.encode(currency0, address(router), 0);

        router.executeActions(actions, params);
    }

    // @notice This tests expected behavior if you DO NOT call sync before a non native settle. (ie. Do not interact with the pool manager properly. You can lose funds.)
    function test_settle_nonNative_withoutSync_loseFunds() public noIsolate {
        MockERC20(Currency.unwrap(currency0)).approve(address(router), type(uint256).max);
        uint256 managerCurrency0BalanceBefore = currency0.balanceOf(address(manager));
        uint256 userCurrency0BalanceBefore = currency0.balanceOf(address(this));

        Actions[] memory actions = new Actions[](9);
        bytes[] memory params = new bytes[](9);

        manager.sync(currency0);
        snapStart("getReserves");
        uint256 reserves = manager.getSyncedReserves();
        snapEnd();
        assertEq(reserves, managerCurrency0BalanceBefore); // reserves are 100.

        actions[0] = Actions.TAKE;
        params[0] = abi.encode(currency0, address(this), 10);

        // Assert that the delta open on the router is -10. (The user owes 10 to the pool).
        actions[1] = Actions.ASSERT_DELTA_EQUALS;
        params[1] = abi.encode(currency0, address(router), -10);

        actions[2] = Actions.TRANSFER_FROM; // NOT syned before sending tokens
        params[2] = abi.encode(currency0, address(this), manager, 10);

        actions[3] = Actions.SETTLE; // calling settle without sync is expecting a native token, but msg.value == 0 so it settles for 0.

        actions[4] = Actions.ASSERT_DELTA_EQUALS;
        params[4] = abi.encode(currency0, address(router), -10);

        actions[5] = Actions.SYNC;
        params[5] = abi.encode(currency0);

        // To now settle the delta, the user owes 10 to the pool.
        actions[6] = Actions.TRANSFER_FROM;
        params[6] = abi.encode(currency0, address(this), manager, 10);

        actions[7] = Actions.SETTLE;

        actions[8] = Actions.ASSERT_DELTA_EQUALS;
        params[8] = abi.encode(currency0, address(router), 0);

        router.executeActions(actions, params);

        // The manager gained 10 currency0.
        assertEq(currency0.balanceOf(address(manager)), managerCurrency0BalanceBefore + 10);
        // The user lost 10 currency0, and can never claim it back.
        assertEq(currency0.balanceOf(address(this)), userCurrency0BalanceBefore - 10);
    }

    function test_settle_failsWithNativeERC20IfNotSyncedInOrder(uint256 value) public noIsolate {
        value = bound(value, 1, uint256(int256(type(int128).max / 2)));
        vm.deal(address(this), value);
        vm.deal(address(manager), value);
        NativeERC20 nativeERC20 = new NativeERC20();

        manager.sync(Currency.wrap(address(nativeERC20)));

        Actions[] memory actions = new Actions[](1);
        bytes[] memory params = new bytes[](1);

        // Revert with NonZeroNativeValue
        actions[0] = Actions.SETTLE_NATIVE;
        params[0] = abi.encode(value);

        vm.expectRevert(IPoolManager.NonZeroNativeValue.selector);
        router.executeActions{value: value}(actions, params);

        // Reference only - see OZ C01 report - previous test confirming vulnerability
        // uint256 balanceBefore = address(this).balance;

        // actions[1] = Actions.SETTLE;
        // params[1] = abi.encode(Currency.wrap(address(nativeERC20)));

        // actions[2] = Actions.ASSERT_DELTA_EQUALS;
        // params[2] = abi.encode(Currency.wrap(address(0)), address(router), value);

        // actions[3] = Actions.ASSERT_DELTA_EQUALS;
        // params[3] = abi.encode(Currency.wrap(address(nativeERC20)), address(router), value);

        // actions[4] = Actions.TAKE;
        // params[4] = abi.encode(Currency.wrap(address(0)), address(this), value);

        // actions[5] = Actions.TAKE;
        // params[5] = abi.encode(Currency.wrap(address(nativeERC20)), address(this), value);

        // uint256 balanceAfter = address(this).balance;
        // assertEq(balanceAfter - balanceBefore, value);
    }
}
