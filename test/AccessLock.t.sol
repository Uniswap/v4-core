// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AccessLockHook, AccessLockHook2, AccessLockHook3} from "../src/test/AccessLockHook.sol";
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
import {PoolIdLibrary} from "../src/types/PoolId.sol";

contract AccessLockTest is Test, Deployers {
    using Pool for Pool.State;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    AccessLockHook accessLockHook;
    AccessLockHook noAccessLockHook;
    AccessLockHook2 accessLockHook2;
    AccessLockHook3 accessLockHook3;
    AccessLockHook accessLockHook4;

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

        (key,) = initPool(
            currency0, currency1, IHooks(address(accessLockHook)), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES
        );

        // Create AccessLockHook2.
        address accessLockAddress2 = address(uint160(Hooks.ACCESS_LOCK_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG));
        deployCodeTo("AccessLockHook.sol:AccessLockHook2", abi.encode(manager), accessLockAddress2);
        accessLockHook2 = AccessLockHook2(accessLockAddress2);

        // Create AccessLockHook3.
        address accessLockAddress3 = address(
            (uint160(makeAddr("hook3")) << 10) >> 10
                | (uint160(Hooks.ACCESS_LOCK_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG))
        );
        deployCodeTo("AccessLockHook.sol:AccessLockHook3", abi.encode(manager), accessLockAddress3);
        accessLockHook3 = AccessLockHook3(accessLockAddress3);

        // Create NoAccessLockHook.
        address noAccessLockHookAddress = address(uint160(Hooks.BEFORE_MODIFY_POSITION_FLAG));
        deployCodeTo("AccessLockHook.sol:AccessLockHook", abi.encode(manager), noAccessLockHookAddress);
        noAccessLockHook = AccessLockHook(noAccessLockHookAddress);

        // Create AccessLockHook with NoOp.
        address accessLockHook4Address = address(
            uint160(
                Hooks.NO_OP_FLAG | Hooks.ACCESS_LOCK_FLAG | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG
                    | Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_DONATE_FLAG
            )
        );
        deployCodeTo("AccessLockHook.sol:AccessLockHook", abi.encode(manager), accessLockHook4Address);
        accessLockHook4 = AccessLockHook(accessLockHook4Address);
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
            abi.encode(10, AccessLockHook.LockAction.Mint) // attempts a mint action that should revert
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
     *  - Burn
     *  - Settle
     *  - Initialize
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

        // Essentially "no-op"s the modifyPosition call and executes a swap before hand, applying the deltas from the swap to the locker.
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

    function test_beforeModifyPosition_burn_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10 && amount < uint128(type(int128).max)); // precision
        // Add liquidity so there is a position to swap over.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        BalanceDelta delta = swapRouter.swap(
            key,
            IPoolManager.SwapParams(true, 10000, TickMath.MIN_SQRT_RATIO + 1),
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 amount1 = uint256(uint128(-delta.amount1()));
        // We have some balance in the manager.
        assertEq(manager.balanceOf(address(this), currency1), amount1);
        manager.transfer(address(key.hooks), currency1, amount1);
        assertEq(manager.balanceOf(address(key.hooks), currency1), amount1);

        modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(-120, 120, 0), abi.encode(amount1, AccessLockHook.LockAction.Burn)
        );

        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfAfter1, balanceOfBefore1 + amount1);
    }

    function test_beforeModifyPosition_settle_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10 && amount < uint128(type(int128).max)); // precision

        // Add liquidity so there is something to take.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        // Can't take more than the manager has.
        vm.assume(amount < key.currency1.balanceOf(address(manager)));

        // Assertions in the hook. Takes and then settles within the hook.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(-120, 120, 1 * 10 ** 18),
            abi.encode(amount, AccessLockHook.LockAction.Settle)
        );
    }

    function test_beforeModifyPosition_initialize_succeedsWithAccessLock() public {
        // The hook intitializes a new pool with the new key at Constants.SQRT_RATIO_1_2;
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams(-120, 120, 1 * 10 ** 18),
            abi.encode(0, AccessLockHook.LockAction.Initialize)
        );

        PoolKey memory newKey = PoolKey({
            currency0: key.currency0,
            currency1: key.currency1,
            fee: Constants.FEE_LOW,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        (Pool.Slot0 memory slot0,,,) = manager.pools(newKey.toId());

        assertEq(slot0.sqrtPriceX96, Constants.SQRT_RATIO_1_2);
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
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
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
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
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
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
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
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
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
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
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
        vm.assume(amount != 0 && amount > 10 && amount < uint128(type(int128).max - 1)); // precision

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
     * BEFORE INITIALIZE TESTS
     *
     */

    function test_beforeInitialize_mint_succeedsWithAccessLock(uint128 amount) public {
        vm.assume(amount != 0 && amount < uint128(type(int128).max));

        PoolKey memory key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Constants.FEE_MEDIUM,
            tickSpacing: 60,
            hooks: IHooks(address(accessLockHook4))
        });

        initializeRouter.initialize(key1, SQRT_RATIO_1_1, abi.encode(amount, AccessLockHook.LockAction.Mint));

        assertEq(manager.balanceOf(address(accessLockHook4), currency1), amount);
    }

    function test_beforeInitialize_take_succeedsWithAccessLock(uint128 amount) public {
        PoolKey memory key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Constants.FEE_MEDIUM,
            tickSpacing: 60,
            hooks: IHooks(address(accessLockHook4))
        });

        // Add liquidity to a different pool there is something to take.
        modifyPositionRouter.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 100 * 10e18}),
            ZERO_BYTES
        );

        // Can't take more than the manager has.
        vm.assume(amount < key.currency1.balanceOf(address(manager)));

        initializeRouter.initialize(key1, SQRT_RATIO_1_1, abi.encode(amount, AccessLockHook.LockAction.Take));

        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(accessLockHook4)), amount);
    }

    function test_beforeInitialize_swap_revertsOnPoolNotInitialized(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10); // precision

        PoolKey memory key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Constants.FEE_MEDIUM,
            tickSpacing: 60,
            hooks: IHooks(address(accessLockHook4))
        });

        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        initializeRouter.initialize(key1, SQRT_RATIO_1_1, abi.encode(amount, AccessLockHook.LockAction.Swap));
    }

    function test_beforeInitialize_modifyPosition_revertsOnPoolNotInitialized(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10); // precision

        PoolKey memory key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Constants.FEE_MEDIUM,
            tickSpacing: 60,
            hooks: IHooks(address(accessLockHook4))
        });

        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        initializeRouter.initialize(key1, SQRT_RATIO_1_1, abi.encode(amount, AccessLockHook.LockAction.ModifyPosition));
    }

    function test_beforeInitialize_donate_revertsOnPoolNotInitialized(uint128 amount) public {
        vm.assume(amount != 0 && amount > 10); // precision

        PoolKey memory key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Constants.FEE_MEDIUM,
            tickSpacing: 60,
            hooks: IHooks(address(accessLockHook4))
        });

        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        initializeRouter.initialize(key1, SQRT_RATIO_1_1, abi.encode(amount, AccessLockHook.LockAction.Donate));
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

        assertEq(address(manager.getCurrentHook()), address(0));

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
        assertEq(address(manager.getCurrentHook()), address(0));

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.LockedBy.selector, address(0), address(0)));
        vm.prank(address(key.hooks));
        manager.modifyPosition(key, IPoolManager.ModifyPositionParams(0, 60, 1 * 10 ** 18), ZERO_BYTES);
    }

    function test_getCurrentHook_isClearedAfterNestedLock() public {
        // Create pool for AccessLockHook3.
        (PoolKey memory keyAccessLockHook3,) =
            initPool(currency0, currency1, IHooks(accessLockHook3), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);
        // Fund AccessLockHook3 with currency0.
        MockERC20(Currency.unwrap(currency0)).transfer(address(accessLockHook3), 10);
        assertEq(MockERC20(Currency.unwrap(currency0)).balanceOf(address(accessLockHook3)), 10);

        // Create pool to donate 10 of currency0 to inside of AccessLockHook3. This means AccessLockHook3 must acquire a new lock and settle.
        // The currentHook addresses are checked inside this nested lock.
        (PoolKey memory _key,) =
            initPool(currency0, currency1, IHooks(address(0)), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);
        // Add liquidity so that the AccessLockHook3 can donate to something.
        modifyPositionRouter.modifyPosition(_key, IPoolManager.ModifyPositionParams(-60, 60, 10 * 10 ** 18), ZERO_BYTES);
        accessLockHook3.setKey(_key);

        // Asserts are in the AccessLockHook3.
        modifyPositionRouter.modifyPosition(
            keyAccessLockHook3, IPoolManager.ModifyPositionParams(0, 60, 1 * 10 ** 18), ZERO_BYTES
        );
    }

    function test_getCurrentHook_isClearedAfterNoOpOnAllHooks() public {
        (PoolKey memory noOpKey,) =
            initPool(currency0, currency1, IHooks(accessLockHook4), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        // Assertions for current hook address in AccessLockHook and respective routers.
        // beforeModifyPosition noOp
        modifyPositionRouter.modifyPosition(
            noOpKey,
            IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 0}),
            abi.encode(0, AccessLockHook.LockAction.NoOp)
        );

        // beforeDonate noOp
        donateRouter.donate(noOpKey, 1 * 10 ** 18, 1 * 10 ** 18, abi.encode(0, AccessLockHook.LockAction.NoOp));

        // beforeSwap noOp
        swapRouter.swap(
            noOpKey,
            IPoolManager.SwapParams(true, 1, TickMath.MIN_SQRT_RATIO + 1),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
            abi.encode(0, AccessLockHook.LockAction.NoOp)
        );
    }
}
