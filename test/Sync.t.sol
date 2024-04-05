// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {Deployers} from "test/utils/Deployers.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "src/types/Currency.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "src/test/PoolSwapTest.sol";
import {IUnlockCallback} from "src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {BadRouter} from "src/test/BadRouter.sol";

contract SyncTest is Test, Deployers, GasSnapshot {
    using CurrencyLibrary for Currency;

    // PoolManager has no balance of currency2.
    // Currency currency2;
    Currency currency2;
    BadRouter badRouter;

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
        (, currency2) = deployMintAndApprove2Currencies();
        badRouter = new BadRouter(manager);
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
        assertEq(balance, currency0Balance);
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
}
