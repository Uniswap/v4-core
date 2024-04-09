// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {Deployers} from "./utils/Deployers.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {IUnlockCallback} from "../src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {BadRouter} from "../src/test/BadRouter.sol";
import {ActionsRouter, Actions} from "../src/test/ActionsRouter.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";

contract SyncTest is Test, Deployers, GasSnapshot {
    using CurrencyLibrary for Currency;

    // PoolManager has no balance of currency2.
    Currency currency2;
    BadRouter badRouter;
    ActionsRouter router;

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
        currency2 = deployMintAndApproveCurrency();
        badRouter = new BadRouter(manager);
        router = new ActionsRouter(manager);
    }

    function test_sync_balanceIsZero() public {
        assertEq(currency2.balanceOf(address(manager)), uint256(0));
        uint256 balance = manager.sync(currency2);

        assertEq(uint256(balance), manager.ZERO_BALANCE()); // return val is ZERO_BALANCE sentinel
        assertEq(manager.getReserves(currency2), manager.ZERO_BALANCE()); // transient val is ZERO_BALANCE sentinel
    }

    function test_sync_balanceIsNonZero() public {
        uint256 currency0Balance = currency0.balanceOf(address(manager));
        assertGt(currency0Balance, uint256(0));

        assertEq(manager.getReserves(currency0), uint256(0));
        uint256 balance = manager.sync(currency0);
        assertEq(balance, currency0Balance, "balance not equal");
    }

    function test_settle_withBalance() public {
        assertGt(currency0.balanceOf(address(manager)), uint256(0));

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        // Sync has not been called.
        assertEq(manager.getReserves(currency0), uint256(0));
        swapRouter.swap(key, params, testSettings, new bytes(0));
        (uint256 balanceCurrency0) = currency0.balanceOf(address(manager));
        assertEq(manager.getReserves(currency0), balanceCurrency0); // Reserves are up to date since settle was called.
    }

    function test_settle_withNoBalance() public {
        assertEq(currency2.balanceOf(address(manager)), uint256(0));

        (Currency cur0, Currency cur1) = currency0 < currency2 ? (currency0, currency2) : (currency2, currency0);
        PoolKey memory key2 =
            PoolKey({currency0: cur0, currency1: cur1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))});

        manager.initialize(key2, SQRT_RATIO_1_1, new bytes(0));

        // Sync has not been called.
        assertEq(manager.getReserves(currency2), uint256(0));
        modifyLiquidityRouter.modifyLiquidity(key2, IPoolManager.ModifyLiquidityParams(-60, 60, 100), new bytes(0));
        (uint256 balanceCurrency2) = currency2.balanceOf(address(manager));
        assertEq(manager.getReserves(currency2), balanceCurrency2);
    }

    function test_settle_revertsIfSyncNotCalled() public {
        MockERC20(Currency.unwrap(key.currency0)).approve(address(badRouter), type(uint256).max);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        BadRouter.TestSettings memory testSettings =
            BadRouter.TestSettings({withdrawTokens: true, settleUsingTransfer: true});

        // Sync has not been called.
        assertEq(manager.getReserves(currency0), uint256(0));

        vm.expectRevert(IPoolManager.ReservesMustBeSynced.selector);
        badRouter.swap(key, params, testSettings, new bytes(0));
    }

    /// @notice When there is no balance and reserves are set to type(uint256).max, a delta of that value should not be applied.
    function test_settle_noBalanceInPool_shouldNotApplyDelta() public {
        assertEq(currency2.balanceOf(address(manager)), uint256(0));

        // Sync has not been called.
        assertEq(manager.getReserves(currency2), uint256(0));

        manager.sync(currency2);
        assertEq(manager.getReserves(currency2), manager.ZERO_BALANCE());

        Actions[] memory actions = new Actions[](1);
        actions[0] = Actions.SETTLE;

        bytes[] memory params = new bytes[](1);
        params[0] = abi.encode(currency2);

        // Calling settle without transferring should not apply the sentinel delta.
        // It should not even assign a valid number to the `paid` variable and should instead under/overflow on calculation.
        // vm.expectRevert();
        router.executeActions(actions, params);
    }

    /// @notice When there is no actual balance in the pool, but reservesBefore is outdated (as sync has not been called),
    /// a delta of type(uint256).max - reservesBefore should not be applied, and no amount should be takeable from the pool.
    function test_settle_afterTake_doesNotApplyDelta() public {
        Currency currency3 = deployMintAndApproveCurrency();

        // Approve the router for a transfer.
        MockERC20(Currency.unwrap(currency3)).approve(address(router), type(uint256).max);

        // Sync has not been called on currency0.
        assertEq(manager.getReserves(currency3), uint256(0));

        manager.sync(currency3);
        // Sync has been called.
        assertEq(manager.getReserves(currency3), manager.ZERO_BALANCE());

        uint256 maxBalanceCurrency3 = uint256(int256(type(int128).max));

        Actions[] memory actions = new Actions[](10);
        bytes[] memory params = new bytes[](10);

        // 1. First supply a large amount of currency3 to the pool, by minting and transfering.
        // Encode a MINT.
        actions[0] = Actions.MINT;
        params[0] = abi.encode(address(this), currency3, maxBalanceCurrency3);

        // Encode a TRANSFER.
        actions[1] = Actions.TRANSFER_FROM;
        params[1] = abi.encode(currency3, address(this), address(manager), maxBalanceCurrency3);

        // Encode a SETTLE.
        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(currency3);

        // 2. Second check that the balances (token balances, reserves balace, and delta balance are as expected).
        // The token balance of the pool should be the full balance.
        // The reserves balance should have been updated to the full balance in settle.
        // And the delta balance should be 0, because it has been fully settled.

        // Assert that the manager balance is the full balance.
        actions[3] = Actions.ASSERT_BALANCE_EQUALS;
        params[3] = abi.encode(currency3, address(manager), maxBalanceCurrency3);

        // Assert that the reserves balance is the full balance.
        actions[4] = Actions.ASSERT_RESERVES_EQUALS;
        params[4] = abi.encode(currency3, maxBalanceCurrency3);

        // Assert that the delta is settled.
        actions[5] = Actions.ASSERT_DELTA_EQUALS;
        params[5] = abi.encode(currency3, address(router), 0);

        // 3. Take the full balance from the pool, but do not call sync. That was reservesBefore > 0. But the next reserves
        // Encode a TAKE.
        actions[6] = Actions.TAKE;
        params[6] = abi.encode(currency3, address(this), maxBalanceCurrency3);

        // Assert that the actual balance of the pool is 0.
        actions[7] = Actions.ASSERT_BALANCE_EQUALS;
        params[7] = abi.encode(currency3, address(manager), 0);

        // Assert that the reserves balance is the old pool balance because sync has not been called.
        actions[8] = Actions.ASSERT_RESERVES_EQUALS;
        params[8] = abi.encode(currency3, maxBalanceCurrency3);

        // Encode a SETTLE.
        actions[9] = Actions.SETTLE;
        params[9] = abi.encode(currency3);

        // vm.expectRevert(); should underflow before any value is applied to `paid` rather than under/overflow on .toUint218()
        router.executeActions(actions, params);
    }
}
