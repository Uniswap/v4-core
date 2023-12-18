// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AccessLockHook, AccessLockHook2, AccessLockHook3, AccessLockFeeHook} from "../src/test/AccessLockHook.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "../src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "../src/test/PoolDonateTest.sol";
import {Constants} from "./utils/Constants.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {Deployers} from "./utils/Deployers.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../src/types/BalanceDelta.sol";
import {Pool} from "../src/libraries/Pool.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {PoolIdLibrary} from "../src/types/PoolId.sol";

contract AccessLockTest is Test, Deployers {
    using Pool for Pool.State;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;

    AccessLockHook accessLockHook;
    AccessLockHook noAccessLockHook;
    AccessLockHook2 accessLockHook2;
    AccessLockHook3 accessLockHook3;
    AccessLockHook accessLockNoOpHook;
    AccessLockFeeHook accessLockFeeHook;

    // global for stack too deep errors
    BalanceDelta delta;

    uint128 amount = 1e18;

    function setUp() public {
        // Initialize managers and routers.
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        // Create AccessLockHook.
        address accessLockAddress = address(
            uint160(
                Hooks.ACCESS_LOCK_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_DONATE_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            )
        );
        deployCodeTo("AccessLockHook.sol:AccessLockHook", abi.encode(manager), accessLockAddress);
        accessLockHook = AccessLockHook(accessLockAddress);

        (key,) =
            initPool(currency0, currency1, IHooks(accessLockAddress), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        // Create AccessLockHook2.
        address accessLockAddress2 = address(uint160(Hooks.ACCESS_LOCK_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        deployCodeTo("AccessLockHook.sol:AccessLockHook2", abi.encode(manager), accessLockAddress2);
        accessLockHook2 = AccessLockHook2(accessLockAddress2);

        // Create AccessLockHook3.
        address accessLockAddress3 = address(
            (uint160(makeAddr("hook3")) << 10) >> 10
                | (uint160(Hooks.ACCESS_LOCK_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG))
        );
        deployCodeTo("AccessLockHook.sol:AccessLockHook3", abi.encode(manager), accessLockAddress3);
        accessLockHook3 = AccessLockHook3(accessLockAddress3);

        // Create NoAccessLockHook.
        address noAccessLockHookAddress = address(uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG));
        deployCodeTo("AccessLockHook.sol:AccessLockHook", abi.encode(manager), noAccessLockHookAddress);
        noAccessLockHook = AccessLockHook(noAccessLockHookAddress);

        // Create AccessLockHook with NoOp.
        address accessLockNoOpHookAddress = address(
            uint160(
                Hooks.NO_OP_FLAG | Hooks.ACCESS_LOCK_FLAG | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG
                    | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_DONATE_FLAG
            )
        );
        deployCodeTo("AccessLockHook.sol:AccessLockHook", abi.encode(manager), accessLockNoOpHookAddress);
        accessLockNoOpHook = AccessLockHook(accessLockNoOpHookAddress);

        // Create AccessLockFeeHook
        address accessLockFeeHookAddress = address(
            uint160(
                Hooks.ACCESS_LOCK_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                    | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            )
        );
        deployCodeTo("AccessLockHook.sol:AccessLockFeeHook", abi.encode(manager), accessLockFeeHookAddress);
        accessLockFeeHook = AccessLockFeeHook(accessLockFeeHookAddress);
    }

    function test_onlyByLocker_revertsForNoAccessLockPool() public {
        (PoolKey memory keyWithoutAccessLockFlag,) =
            initPool(currency0, currency1, IHooks(noAccessLockHook), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolManager.LockedBy.selector, address(modifyLiquidityRouter), address(noAccessLockHook)
            )
        );
        modifyLiquidityRouter.modifyLiquidity(
            keyWithoutAccessLockFlag,
            IPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 1e18}),
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
     *  - ModifyLiquidity
     *  - Donate
     *  - Burn
     *  - Settle
     *  - Initialize
     * Each of these calls is then tested from every callback after the
     * currentHook gets set (beforeAddLiquidity, beforeSwap, and beforeDonate).
     *
     */

    /**
     *
     * BEFORE MODIFY POSITION TESTS
     *
     */
    function test_beforeAddLiquidity_mint_succeedsWithAccessLock() public {
        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        delta = modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18), abi.encode(amount, AccessLockHook.LockAction.Mint)
        );

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyLiquidityRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));

        assertEq(manager.balanceOf(address(accessLockHook), currency1.toId()), amount);
    }

    function test_beforeRemoveLiquidity_mint_succeedsWithAccessLock() public {
        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(
            key, REMOVE_LIQ_PARAMS, abi.encode(amount, AccessLockHook.LockAction.Mint)
        );

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // The balance of our contract should be equal to our original balance because we added and removed our liquidity.
        // Note: the balance is off by one and is a known issue documented here: https://github.com/Uniswap/v3-core/issues/570
        assertTrue(balanceOfBefore0 - balanceOfAfter0 <= 1);
        assertTrue(balanceOfBefore1 - balanceOfAfter1 - amount <= 1);

        assertEq(manager.balanceOf(address(accessLockHook), currency1.toId()), amount);
    }

    function test_beforeAddLiquidity_take_succeedsWithAccessLock() public {
        // Add liquidity so there is something to take.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Hook only takes currency 1 rn.
        delta = modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-60, 60, 1e18), abi.encode(amount, AccessLockHook.LockAction.Take)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyLiquidityRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));
        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(accessLockHook)), amount);
    }

    function test_beforeRemoveLiquidity_take_succeedsWithAccessLock() public {
        // Add liquidity so there is something to take.
        delta = modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
        uint128 takeAmount = uint128(key.currency1.balanceOf(address(manager)));

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Hook only takes currency 1 rn.
        modifyLiquidityRouter.modifyLiquidity(
            key, REMOVE_LIQ_PARAMS, abi.encode(takeAmount, AccessLockHook.LockAction.Take)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // The balance of our contract should be equal to our original balance because we added and removed our liquidity.
        // Note: the balance is off by one and is a known issue documented here: https://github.com/Uniswap/v3-core/issues/570
        assertTrue(balanceOfBefore0 + uint256(uint128(delta.amount0())) - balanceOfAfter0 <= 1);
        assertTrue(balanceOfBefore1 + uint256(uint128(delta.amount1())) - balanceOfAfter1 - takeAmount <= 1);
        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(accessLockHook)), takeAmount);
    }

    function test_beforeAddLiquidity_swap_succeedsWithAccessLock() public {
        // Add liquidity so there is something to swap over.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Essentially "no-op"s the modifyPosition call and executes a swap before hand, applying the deltas from the swap to the locker.
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-120, 120, 1e18), abi.encode(amount, AccessLockHook.LockAction.Swap)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Balance decreases because we are swapping currency0 for currency1.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        // Balance should be greater in currency1.
        assertGt(balanceOfAfter1, balanceOfBefore1);
    }

    function test_beforeAddLiquidity_addLiquidity_succeedsWithAccessLock() public {
        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(-120, 120, 10e18),
            abi.encode(amount, AccessLockHook.LockAction.ModifyLiquidity)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Should have less balance in both currencies.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        assertLt(balanceOfAfter1, balanceOfBefore1);
    }

    function test_beforeAddLiquidity_donate_succeedsWithAccessLock() public {
        // Add liquidity so there is a position to receive fees.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(-120, 120, 1e18),
            abi.encode(amount, AccessLockHook.LockAction.Donate)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Should have less balance in both currencies.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        assertLt(balanceOfAfter1, balanceOfBefore1);
    }

    function test_beforeAddLiquidity_burn_succeedsWithAccessLock() public {
        // Add liquidity so there is a position to swap over.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        delta = swapRouter.swap(
            key,
            IPoolManager.SwapParams(true, 10000, TickMath.MIN_SQRT_RATIO + 1),
            PoolSwapTest.TestSettings({withdrawTokens: false, settleUsingTransfer: true, currencyAlreadySent: false}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 amount1 = uint256(uint128(-delta.amount1()));
        // We have some balance in the manager.
        assertEq(manager.balanceOf(address(this), currency1.toId()), amount1);
        manager.transfer(address(key.hooks), currency1.toId(), amount1);
        assertEq(manager.balanceOf(address(key.hooks), currency1.toId()), amount1);

        delta = modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(-120, 120, 1e18),
            abi.encode(amount1, AccessLockHook.LockAction.Burn)
        );

        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfAfter1, balanceOfBefore1 + amount1 - uint256(uint128(delta.amount1())));
    }

    function test_beforeAddLiquidity_settle_succeedsWithAccessLock() public {
        // Add liquidity so there is something to take.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        // Assertions in the hook. Takes and then settles within the hook.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(-120, 120, 1e18),
            abi.encode(amount, AccessLockHook.LockAction.Settle)
        );
    }

    function test_beforeAddLiquidity_initialize_succeedsWithAccessLock() public {
        // The hook intitializes a new pool with the new key at Constants.SQRT_RATIO_1_2;
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(-120, 120, 1e18),
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

    function test_beforeSwap_mint_succeedsWithAccessLock() public {
        // Add liquidity so there is something to swap against.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Small amount to swap (like NoOp). This way we can expect balances to just be from the hook applied delta.
        delta = swapRouter.swap(
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

        assertEq(manager.balanceOf(address(accessLockHook), currency1.toId()), amount);
    }

    function test_beforeSwap_take_succeedsWithAccessLock() public {
        // Add liquidity so there is something to take.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Hook only takes currency 1 rn.
        // Use small amount to NoOp.
        delta = swapRouter.swap(
            key,
            IPoolManager.SwapParams(true, 1, TickMath.MIN_SQRT_RATIO + 1),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
            abi.encode(amount, AccessLockHook.LockAction.Take)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyLiquidityRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));
        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(accessLockHook)), amount);
    }

    function test_beforeSwap_swap_succeedsWithAccessLock() public {
        // Add liquidity so there is something to swap over.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
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

    function test_beforeSwap_addLiquidity_succeedsWithAccessLock() public {
        // Add liquidity so there is something to swap over.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Make the swap amount small (like a NoOp).
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(true, 1, TickMath.MIN_SQRT_RATIO + 1),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
            abi.encode(amount, AccessLockHook.LockAction.ModifyLiquidity)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Should have less balance in both currencies.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        assertLt(balanceOfAfter1, balanceOfBefore1);
    }

    function test_beforeSwap_donate_succeedsWithAccessLock() public {
        // Add liquidity so there is a position to receive fees.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
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

    function test_beforeDonate_mint_succeedsWithAccessLock() public {
        // Add liquidity so there is something to donate to.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        delta = donateRouter.donate(key, 1e18, 1e18, abi.encode(amount, AccessLockHook.LockAction.Mint));

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the donateRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));

        assertEq(manager.balanceOf(address(accessLockHook), currency1.toId()), amount);
    }

    function test_beforeDonate_take_succeedsWithAccessLock() public {
        // Add liquidity so there is something to take.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Hook only takes currency 1 rn.
        delta = donateRouter.donate(key, 1e18, 1e18, abi.encode(amount, AccessLockHook.LockAction.Take));
        // Take applies a positive delta in currency1.
        // Donate applies a positive delta in currency0 and currency1.
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyLiquidityRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));
        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(accessLockHook)), amount);
    }

    function test_beforeDonate_swap_succeedsWithAccessLock() public {
        // Add liquidity so there is something to swap over.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

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

    function test_beforeDonate_addLiquidity_succeedsWithAccessLock() public {
        // Add liquidity so there is something to donate to.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        donateRouter.donate(key, 1e18, 1e18, abi.encode(amount, AccessLockHook.LockAction.ModifyLiquidity));

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        // Should have less balance in both currencies from adding liquidity AND donating.
        assertLt(balanceOfAfter0, balanceOfBefore0);
        assertLt(balanceOfAfter1, balanceOfBefore1);
    }

    function test_beforeDonate_donate_succeedsWithAccessLock() public {
        // Add liquidity so there is a position to receive fees.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        // Make the swap amount small (like a NoOp).
        donateRouter.donate(key, 1e18, 1e18, abi.encode(amount, AccessLockHook.LockAction.Donate));

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

    function test_beforeInitialize_mint_succeedsWithAccessLock() public {
        PoolKey memory key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Constants.FEE_MEDIUM,
            tickSpacing: 60,
            hooks: IHooks(address(accessLockNoOpHook))
        });

        initializeRouter.initialize(key1, SQRT_RATIO_1_1, abi.encode(amount, AccessLockHook.LockAction.Mint));

        assertEq(manager.balanceOf(address(accessLockNoOpHook), currency1.toId()), amount);
    }

    function test_beforeInitialize_take_succeedsWithAccessLock() public {
        PoolKey memory key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Constants.FEE_MEDIUM,
            tickSpacing: 60,
            hooks: IHooks(address(accessLockNoOpHook))
        });

        // Add liquidity to a different pool there is something to take.
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000e18}),
            ZERO_BYTES
        );

        initializeRouter.initialize(key1, SQRT_RATIO_1_1, abi.encode(amount, AccessLockHook.LockAction.Take));

        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(accessLockNoOpHook)), amount);
    }

    function test_beforeInitialize_swap_revertsOnPoolNotInitialized() public {
        PoolKey memory key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Constants.FEE_MEDIUM,
            tickSpacing: 60,
            hooks: IHooks(address(accessLockNoOpHook))
        });

        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        initializeRouter.initialize(key1, SQRT_RATIO_1_1, abi.encode(amount, AccessLockHook.LockAction.Swap));
    }

    function test_beforeInitialize_addLiquidity_revertsOnPoolNotInitialized() public {
        PoolKey memory key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Constants.FEE_MEDIUM,
            tickSpacing: 60,
            hooks: IHooks(address(accessLockNoOpHook))
        });

        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        initializeRouter.initialize(key1, SQRT_RATIO_1_1, abi.encode(amount, AccessLockHook.LockAction.ModifyLiquidity));
    }

    function test_beforeInitialize_donate_revertsOnPoolNotInitialized() public {
        PoolKey memory key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: Constants.FEE_MEDIUM,
            tickSpacing: 60,
            hooks: IHooks(address(accessLockNoOpHook))
        });

        vm.expectRevert(IPoolManager.PoolNotInitialized.selector);
        initializeRouter.initialize(key1, SQRT_RATIO_1_1, abi.encode(amount, AccessLockHook.LockAction.Donate));
    }

    /**
     *
     * HOOK FEE TESTS
     *
     */

    function test_hookFees_takesFeeOnWithdrawal() public {
        (key,) = initPool(
            currency0, currency1, IHooks(address(accessLockFeeHook)), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES
        );

        (uint256 userBalanceBefore0, uint256 poolBalanceBefore0, uint256 reservesBefore0) = _fetchBalances(currency0);
        (uint256 userBalanceBefore1, uint256 poolBalanceBefore1, uint256 reservesBefore1) = _fetchBalances(currency1);

        // add liquidity
        delta = modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        (uint256 userBalanceAfter0, uint256 poolBalanceAfter0, uint256 reservesAfter0) = _fetchBalances(currency0);
        (uint256 userBalanceAfter1, uint256 poolBalanceAfter1, uint256 reservesAfter1) = _fetchBalances(currency1);

        assert(delta.amount0() > 0 && delta.amount1() > 0);
        assertEq(userBalanceBefore0 - uint128(delta.amount0()), userBalanceAfter0, "addLiq user balance currency0");
        assertEq(userBalanceBefore1 - uint128(delta.amount1()), userBalanceAfter1, "addLiq user balance currency1");
        assertEq(poolBalanceBefore0 + uint128(delta.amount0()), poolBalanceAfter0, "addLiq pool balance currency0");
        assertEq(poolBalanceBefore1 + uint128(delta.amount1()), poolBalanceAfter1, "addLiq pool balance currency1");
        assertEq(reservesBefore0 + uint128(delta.amount0()), reservesAfter0, "addLiq reserves currency0");
        assertEq(reservesBefore1 + uint128(delta.amount1()), reservesAfter1, "addLiq reserves currency1");

        (userBalanceBefore0, poolBalanceBefore0, reservesBefore0) =
            (userBalanceAfter0, poolBalanceAfter0, reservesAfter0);
        (userBalanceBefore1, poolBalanceBefore1, reservesBefore1) =
            (userBalanceAfter1, poolBalanceAfter1, reservesAfter1);

        // remove liquidity, a 40 bip fee should be taken
        LIQ_PARAMS.liquidityDelta *= -1;
        delta = modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        (userBalanceAfter0, poolBalanceAfter0, reservesAfter0) = _fetchBalances(currency0);
        (userBalanceAfter1, poolBalanceAfter1, reservesAfter1) = _fetchBalances(currency1);

        assert(delta.amount0() < 0 && delta.amount1() < 0);

        uint256 totalWithdraw0 = uint128(-delta.amount0()) - (uint128(-delta.amount0()) * 40 / 10000);
        uint256 totalWithdraw1 = uint128(-delta.amount1()) - (uint128(-delta.amount1()) * 40 / 10000);

        assertEq(userBalanceBefore0 + totalWithdraw0, userBalanceAfter0, "removeLiq user balance currency0");
        assertEq(userBalanceBefore1 + totalWithdraw1, userBalanceAfter1, "removeLiq user balance currency1");
        assertEq(poolBalanceBefore0 - uint128(-delta.amount0()), poolBalanceAfter0, "removeLiq pool balance currency0");
        assertEq(poolBalanceBefore1 - uint128(-delta.amount1()), poolBalanceAfter1, "removeLiq pool balance currency1");
        assertEq(reservesBefore0 - uint128(-delta.amount0()), reservesAfter0, "removeLiq reserves currency0");
        assertEq(reservesBefore1 - uint128(-delta.amount1()), reservesAfter1, "removeLiq reserves currency1");
    }

    function test_hookFees_takesFeeOnInputOfSwap() public {
        (key,) = initPool(
            currency0, currency1, IHooks(address(accessLockFeeHook)), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES
        );

        // add liquidity
        delta = modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);

        // now swap, with a hook fee of 55 bips
        (uint256 userBalanceBefore0, uint256 poolBalanceBefore0, uint256 reservesBefore0) = _fetchBalances(currency0);
        (uint256 userBalanceBefore1, uint256 poolBalanceBefore1, uint256 reservesBefore1) = _fetchBalances(currency1);

        delta = swapRouter.swap(
            key,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100000, sqrtPriceLimitX96: SQRT_RATIO_1_2}),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
            ZERO_BYTES
        );

        assert(delta.amount0() > 0 && delta.amount1() < 0);

        uint256 amountIn0 = uint128(delta.amount0());
        uint256 userAmountOut1 = uint128(-delta.amount1()) - (uint128(-delta.amount1()) * 55 / 10000);

        (uint256 userBalanceAfter0, uint256 poolBalanceAfter0, uint256 reservesAfter0) = _fetchBalances(currency0);
        (uint256 userBalanceAfter1, uint256 poolBalanceAfter1, uint256 reservesAfter1) = _fetchBalances(currency1);

        assertEq(userBalanceBefore0 - amountIn0, userBalanceAfter0, "swap user balance currency0");
        assertEq(userBalanceBefore1 + userAmountOut1, userBalanceAfter1, "swap user balance currency1");
        assertEq(poolBalanceBefore0 + amountIn0, poolBalanceAfter0, "swap pool balance currency0");
        assertEq(poolBalanceBefore1 - uint128(-delta.amount1()), poolBalanceAfter1, "swap pool balance currency1");
        assertEq(reservesBefore0 + amountIn0, reservesAfter0, "swap reserves currency0");
        assertEq(reservesBefore1 - uint128(-delta.amount1()), reservesAfter1, "swap reserves currency1");
    }

    /**
     *
     * EDGE CASE TESTS
     *
     */

    function test_onlyByLocker_revertsWhenHookIsNotCurrentHook() public {
        // Call first access lock hook. Should succeed.
        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        delta = modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18), abi.encode(amount, AccessLockHook.LockAction.Mint)
        );

        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyLiquidityRouter (delta) AND the hook (amount).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(amount + uint256(uint128(delta.amount1()))));

        assertEq(manager.balanceOf(address(accessLockHook), currency1.toId()), amount);

        assertEq(address(manager.getCurrentHook()), address(0));

        (PoolKey memory keyAccessLockHook2,) =
            initPool(currency0, currency1, IHooks(accessLockHook2), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        // Delegates the beforeAddLiquidity call to the hook in `key` which tries to mint on manager
        //  but reverts because hook in `key` is not the current hook.
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolManager.LockedBy.selector, address(modifyLiquidityRouter), address(accessLockHook2)
            )
        );
        delta = modifyLiquidityRouter.modifyLiquidity(
            keyAccessLockHook2, IPoolManager.ModifyLiquidityParams(0, 60, 1e18), abi.encode(true, key)
        );
    }

    function test_onlyByLocker_succeedsAfterHookMakesNestedCall() public {
        (PoolKey memory keyWithNoHook,) =
            initPool(currency0, currency1, IHooks(address(0)), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        (PoolKey memory keyAccessLockHook2,) =
            initPool(currency0, currency1, IHooks(accessLockHook2), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        modifyLiquidityRouter.modifyLiquidity(
            keyAccessLockHook2, IPoolManager.ModifyLiquidityParams(0, 60, 1e18), abi.encode(false, keyWithNoHook)
        );
        assertEq(manager.balanceOf(address(accessLockHook2), currency1.toId()), 10);
    }

    function test_onlyByLocker_revertsWhenThereIsNoOutsideLock() public {
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18), ZERO_BYTES);
        assertEq(address(manager.getCurrentHook()), address(0));

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.LockedBy.selector, address(0), address(0)));
        vm.prank(address(key.hooks));
        manager.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18), ZERO_BYTES);
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
        modifyLiquidityRouter.modifyLiquidity(
            _key, IPoolManager.ModifyLiquidityParams(-60, 60, 10 * 10 ** 18), ZERO_BYTES
        );
        accessLockHook3.setKey(_key);

        // Asserts are in the AccessLockHook3.
        modifyLiquidityRouter.modifyLiquidity(
            keyAccessLockHook3, IPoolManager.ModifyLiquidityParams(0, 60, 1e18), ZERO_BYTES
        );
    }

    function test_getCurrentHook_isClearedAfterNoOpOnAllHooks() public {
        (PoolKey memory noOpKey,) =
            initPool(currency0, currency1, IHooks(accessLockNoOpHook), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        // Assertions for current hook address in AccessLockHook and respective routers.
        // beforeAddLiquidity noOp
        modifyLiquidityRouter.modifyLiquidity(
            noOpKey,
            IPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 1e18}),
            abi.encode(0, AccessLockHook.LockAction.NoOp)
        );

        // beforeDonate noOp
        donateRouter.donate(noOpKey, 1e18, 1e18, abi.encode(0, AccessLockHook.LockAction.NoOp));

        // beforeSwap noOp
        swapRouter.swap(
            noOpKey,
            IPoolManager.SwapParams(true, 1, TickMath.MIN_SQRT_RATIO + 1),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
            abi.encode(0, AccessLockHook.LockAction.NoOp)
        );
    }

    function _fetchBalances(Currency currency)
        internal
        view
        returns (uint256 userBalance, uint256 poolBalance, uint256 reserves)
    {
        userBalance = currency.balanceOf(address(this));
        poolBalance = currency.balanceOf(address(manager));
        reserves = manager.reservesOf(currency);
    }
}
