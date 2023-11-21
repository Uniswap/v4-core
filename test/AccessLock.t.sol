// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AccessLockHook, AccessLockHook2} from "../src/test/AccessLockHook.sol";
import {NoAccessLockHook} from "../src/test/NoAccessLockHook.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolModifyPositionTest} from "../src/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "../src/test/PoolDonateTest.sol";
import {Constants} from "./utils/Constants.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {Deployers} from "./utils/Deployers.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {Pool} from "../src/libraries/Pool.sol";
import {TickMath} from "../src/libraries/TickMath.sol";

contract AccessLockTest is Test, Deployers {
    using Pool for Pool.State;
    using CurrencyLibrary for Currency;

    AccessLockHook accessLockHook;
    NoAccessLockHook noAccessLockHook;
    AccessLockHook2 accessLockHook2;

    function setUp() public {
        // Initialize managers and routers.
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        // Create AccessLockHook.
        address accessLockAddress = address(
            uint160(
                Hooks.ACCESS_LOCK_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG
                    | Hooks.BEFORE_DONATE_FLAG
            )
        );
        deployCodeTo("AccessLockHook.sol:AccessLockHook", abi.encode(manager), accessLockAddress);
        accessLockHook = AccessLockHook(accessLockAddress);

        // Create AccessLockHook2.
        address accessLockAddress2 = address(uint160(Hooks.ACCESS_LOCK_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG));
        deployCodeTo("AccessLockHook.sol:AccessLockHook2", abi.encode(manager), accessLockAddress2);
        accessLockHook2 = AccessLockHook2(accessLockAddress2);

        // Create NoAccessLockHook.
        address noAccessLockHookAddress = address(uint160(Hooks.BEFORE_MODIFY_POSITION_FLAG));
        deployCodeTo("NoAccessLockHook.sol:NoAccessLockHook", abi.encode(manager), noAccessLockHookAddress);
        noAccessLockHook = NoAccessLockHook(noAccessLockHookAddress);

        (key,) = initPool(
            currency0, currency1, IHooks(address(accessLockHook)), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES
        );
    }

    function test_onlyByLocker_revertsForNoAccessLockPool() public {
        (PoolKey memory keyWithoutAccessLockFlag,) =
            initPool(currency0, currency1, IHooks(noAccessLockHook), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolManager.LockedBy.selector, address(modifyPositionRouter), address(noAccessLockHook)
            )
        );
        modifyPositionRouter.modifyPosition(
            keyWithoutAccessLockFlag,
            IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 0}),
            ZERO_BYTES
        );
    }
    /**
     *
     *
     * The following test suite tests that appropriate hooks can call
     *  every function gated by the `onlyByLocker` modifier.
     *  We call these "LockActions".
     *  LockActions:
     *  - Mint
     *  - Take
     *  - Swap
     *  - ModifyPosition
     *  - Donate
     *
     * Each of these calls is then tested from every callback after the
     * currentHook gets set (beforeModifyPosition, beforeSwap, and beforeDonate).
     *
     */

    /**
     *
     * BEFORE MODIFY POSITION TESTS
     *
     */
    function test_beforeModifyPosition_mint_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount < uint128(type(int128).max));
        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        BalanceDelta delta = modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(0, 60, 1 * 10 ** 18),
            abi.encode(amount, AccessLockHook.LockAction.Mint)
        );

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyPositionRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));

        assertEq(manager.balanceOf(address(accessLockHook), currency1), amount);
    }

    function test_beforeModifyPosition_take_succeedsWithAccessLock(uint128 amount) public {
        // Add liquidity so there is something to take.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );
        // Can't take more than the manager has.
        vm.assume(amount < key.currency1.balanceOf(address(manager)));

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Hook only takes currency 1 rn.
        BalanceDelta delta = modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(-60, 60, 1 * 10 ** 18),
            abi.encode(amount, AccessLockHook.LockAction.Take)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyPositionRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));
        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(accessLockHook)), amount);
    }

    function test_beforeModifyPosition_swap_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10); // precision

        // Add liquidity so there is something to swap over.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Just no-op.
        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(-120, 120, 0), abi.encode(amount, AccessLockHook.LockAction.Swap)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Balance decreases because we are swapping currency0 for currency1.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        // Balance should be greater in currency1.
        assertGt(balanceOfAfter1, balanceOfBefore1);
    }

    function test_beforeModifyPosition_modifyPosition_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10 && amount < Pool.tickSpacingToMaxLiquidityPerTick(60));

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(-120, 120, 1 * 10 ** 18),
            abi.encode(amount, AccessLockHook.LockAction.ModifyPosition)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Should have less balance in both currencies.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        assertLt(balanceOfAfter1, balanceOfBefore1);
    }

    function test_beforeModifyPosition_donate_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10 && amount < uint128(type(int128).max)); // precision
        // Add liquidity so there is a position to receive fees.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(-120, 120, 1 * 10 ** 18),
            abi.encode(amount, AccessLockHook.LockAction.Donate)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Should have less balance in both currencies.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        assertLt(balanceOfAfter1, balanceOfBefore1);
    }

    /**
     *
     * BEFORE SWAP TESTS
     *
     */

    function test_beforeSwap_mint_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount < uint128(type(int128).max));

        // Add liquidity so there is something to swap against.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Small amount to swap (like NoOp). This way we can expect balances to just be from the hook applied delta.
        BalanceDelta delta = swapRouter.swap(
            key,
            IPoolManager.SwapParams(true, 1, TickMath.MIN_SQRT_RATIO + 1),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            abi.encode(amount, AccessLockHook.LockAction.Mint)
        );

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyPositionRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));

        assertEq(manager.balanceOf(address(accessLockHook), currency1), amount);
    }

    function test_beforeSwap_take_succeedsWithAccessLock(uint128 amount) public {
        // Add liquidity so there is something to take.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        // Can't take more than the manager has.
        vm.assume(amount < key.currency1.balanceOf(address(manager)));

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Hook only takes currency 1 rn.
        // Use small amount to NoOp.
        BalanceDelta delta = swapRouter.swap(
            key,
            IPoolManager.SwapParams(true, 1, TickMath.MIN_SQRT_RATIO + 1),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            abi.encode(amount, AccessLockHook.LockAction.Take)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyPositionRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));
        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(accessLockHook)), amount);
    }

    function test_beforeSwap_swap_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10); // precision

        // Add liquidity so there is something to swap over.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        swapRouter.swap(
            key,
            // Use small amounts so that the zeroForOne swap is larger
            IPoolManager.SwapParams(false, 1, TickMath.MAX_SQRT_RATIO - 1),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            abi.encode(amount, AccessLockHook.LockAction.Swap)
        );

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // The larger swap is zeroForOne
        // Balance decreases because we are swapping currency0 for currency1.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        // Balance should be greater in currency1.
        assertGt(balanceOfAfter1, balanceOfBefore1);
    }

    function test_beforeSwap_modifyPosition_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10 && amount < Pool.tickSpacingToMaxLiquidityPerTick(60));

        // Add liquidity so there is something to swap over.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Make the swap amount small (like a NoOp).
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(true, 1, TickMath.MIN_SQRT_RATIO + 1),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            abi.encode(amount, AccessLockHook.LockAction.ModifyPosition)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Should have less balance in both currencies.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        assertLt(balanceOfAfter1, balanceOfBefore1);
    }

    function test_beforeSwap_donate_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10 && amount < uint128(type(int128).max)); // precision
        // Add liquidity so there is a position to receive fees.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Make the swap amount small (like a NoOp).
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(true, 1, TickMath.MIN_SQRT_RATIO + 1),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true}),
            abi.encode(amount, AccessLockHook.LockAction.Donate)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Should have less balance in both currencies.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        assertLt(balanceOfAfter1, balanceOfBefore1);
    }

    /**
     *
     * BEFORE DONATE TESTS
     *
     */

    function test_beforeDonate_mint_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount < uint128(type(int128).max));

        // Add liquidity so there is something to donate to.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        BalanceDelta delta =
            donateRouter.donate(key, 1 * 10 ** 18, 1 * 10 ** 18, abi.encode(amount, AccessLockHook.LockAction.Mint));

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the donateRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));

        assertEq(manager.balanceOf(address(accessLockHook), currency1), amount);
    }

    function test_beforeDonate_take_succeedsWithAccessLock(uint128 amount) public {
        // Add liquidity so there is something to take.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        // Can't take more than the manager has.
        vm.assume(amount < key.currency1.balanceOf(address(manager)));

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Hook only takes currency 1 rn.
        BalanceDelta delta =
            donateRouter.donate(key, 1 * 10 ** 18, 1 * 10 ** 18, abi.encode(amount, AccessLockHook.LockAction.Take));
        // Take applies a positive delta in currency1.
        // Donate applies a positive delta in currency0 and currency1.
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyPositionRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));
        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(accessLockHook)), amount);
    }

    function test_beforeDonate_swap_succeedsWithAccessLock(uint128 amount) public {
        // Add liquidity so there is something to swap over.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        // greater than 10 for precision, less than currency1 balance so that we still have liquidity we can donate to
        vm.assume(amount != 0 && amount > 10 && amount < currency1.balanceOf(address(manager)));

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Donate small amounts (NoOp) so we know the swap amount dominates.
        donateRouter.donate(key, 1, 1, abi.encode(amount, AccessLockHook.LockAction.Swap));

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Balance of currency0 decreases bc we 1) donate and 2) swap zeroForOne.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        // Since the donate amount is small, and we swapped zeroForOne, we expect balance of currency1 to increase.
        assertGt(balanceOfAfter1, balanceOfBefore1);
    }

    function test_beforeDonate_modifyPosition_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10 && amount < Pool.tickSpacingToMaxLiquidityPerTick(60));

        // Add liquidity so there is something to donate to.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        donateRouter.donate(
            key, 1 * 10 ** 18, 1 * 10 ** 18, abi.encode(amount, AccessLockHook.LockAction.ModifyPosition)
        );

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Should have less balance in both currencies from adding liquidity AND donating.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        assertLt(balanceOfAfter1, balanceOfBefore1);
    }

    function test_beforeDonate_donate_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10 && amount < uint128(type(int128).max)); // precision

        // Add liquidity so there is a position to receive fees.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Make the swap amount small (like a NoOp).
        donateRouter.donate(key, 1 * 10 ** 18, 1 * 10 ** 18, abi.encode(amount, AccessLockHook.LockAction.Donate));

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Should have less balance in both currencies.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        assertLt(balanceOfAfter1, balanceOfBefore1);
    }

    /**
     *
     * EDGE CASE TESTS
     *
     */

    function test_onlyByLocker_revertsWhenHookIsNotCurrentHook() public {
        // Call first access lock hook. Should succeed.
        uint256 amount = 100;
        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        BalanceDelta delta = modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(0, 60, 1 * 10 ** 18),
            abi.encode(amount, AccessLockHook.LockAction.Mint)
        );

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyPositionRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));

        assertEq(manager.balanceOf(address(accessLockHook), currency1), amount);

        assertEq(manager.getCurrentHook(), address(0));

        (PoolKey memory keyAccessLockHook2,) =
            initPool(currency0, currency1, IHooks(accessLockHook2), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        // Delegates the beforeModifyPosition call to the hook in `key` which tries to mint on manager
        //  but reverts because hook in `key` is not the current hook.
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolManager.LockedBy.selector, address(modifyPositionRouter), address(accessLockHook2)
            )
        );
        delta = modifyPositionRouter.modifyPosition(
            keyAccessLockHook2, IPoolManager.ModifyPositionParams(0, 60, 1 * 10 ** 18), abi.encode(true, key)
        );
    }

    function test_onlyByLocker_succeedsAfterHookMakesNestedCall() public {
        (PoolKey memory keyWithNoHook,) =
            initPool(currency0, currency1, IHooks(address(0)), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        (PoolKey memory keyAccessLockHook2,) =
            initPool(currency0, currency1, IHooks(accessLockHook2), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        modifyPositionRouter.modifyPosition(
            keyAccessLockHook2, IPoolManager.ModifyPositionParams(0, 60, 1 * 10 ** 18), abi.encode(false, keyWithNoHook)
        );
        assertEq(manager.balanceOf(address(accessLockHook2), currency1), 10);
    }

    function test_onlyByLocker_revertsWhenThereIsNoOutsideLock() public {
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(0, 60, 1 * 10 ** 18), ZERO_BYTES);
        assertEq(manager.getCurrentHook(), address(0));

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.LockedBy.selector, address(0), address(0)));
        vm.prank(address(key.hooks));
        manager.modifyPosition(key, IPoolManager.ModifyPositionParams(0, 60, 1 * 10 ** 18), ZERO_BYTES);
    }
}
