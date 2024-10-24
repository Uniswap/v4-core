// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "./utils/Deployers.sol";
import {FeeTakingHook} from "../src/test/FeeTakingHook.sol";
import {LPFeeTakingHook} from "../src/test/LPFeeTakingHook.sol";
import {CustomCurveHook} from "../src/test/CustomCurveHook.sol";
import {DeltaReturningHook} from "../src/test/DeltaReturningHook.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {PoolId} from "../src/types/PoolId.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {Currency} from "../src/types/Currency.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";

contract CustomAccountingTest is Test, Deployers {
    using SafeCast for *;

    address hook;

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    }

    function _setUpDeltaReturnFuzzPool() internal {
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        address impl = address(new DeltaReturningHook(manager));
        _etchHookAndInitPool(hookAddr, impl);
    }

    function _setUpCustomCurvePool() internal {
        address hookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        address impl = address(new CustomCurveHook(manager));
        _etchHookAndInitPool(hookAddr, impl);
    }

    function _setUpFeeTakingPool() internal {
        address hookAddr = address(
            uint160(
                Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
                    | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
                    | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
            )
        );
        address impl = address(new FeeTakingHook(manager));
        _etchHookAndInitPool(hookAddr, impl);
    }

    function _setUpLPFeeTakingPool() internal {
        address hookAddr = address(
            uint160(
                Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
                    | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
            )
        );
        address impl = address(new LPFeeTakingHook(manager));
        _etchHookAndInitPool(hookAddr, impl);
    }

    function _etchHookAndInitPool(address hookAddr, address implAddr) internal {
        vm.etch(hookAddr, implAddr.code);
        hook = hookAddr;

        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(hookAddr), 100, SQRT_PRICE_1_1);
    }

    // ------------------------ SWAP  ------------------------

    function test_swap_afterSwapFeeOnUnspecified_exactInput() public {
        _setUpFeeTakingPool();
        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        uint256 amountToSwap = 1000;
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(amountToSwap),
            sqrtPriceLimitX96: SQRT_PRICE_1_2
        });
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        vm.snapshotGasLastCall("swap CA fee on unspecified");

        // input is 1000 for output of 998 with this much liquidity available
        // plus a fee of 1.23% on unspecified (output) => (998*123)/10000 = 12
        assertEq(currency0.balanceOf(address(this)), balanceBefore0 - amountToSwap, "amount 0");
        assertEq(currency1.balanceOf(address(this)), balanceBefore1 + (998 - 12), "amount 1");
    }

    function test_swap_afterSwapFeeOnUnspecified_exactOutput() public {
        _setUpFeeTakingPool();

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        uint256 amountToSwap = 1000;
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(amountToSwap),
            sqrtPriceLimitX96: SQRT_PRICE_1_2
        });
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        // input is 1002 for output of 1000 with this much liquidity available
        // plus a fee of 1.23% on unspecified (input) => (1002*123)/10000 = 12
        assertEq(currency0.balanceOf(address(this)), balanceBefore0 - 1002 - 12, "amount 0");
        assertEq(currency1.balanceOf(address(this)), balanceBefore1 + amountToSwap, "amount 1");
    }

    function test_swap_beforeSwapNoOpsSwap_exactInput() public {
        _setUpCustomCurvePool();

        // add liquidity by sending tokens straight into the contract
        key.currency0.transfer(hook, 10e18);
        key.currency1.transfer(hook, 10e18);

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        uint256 amountToSwap = 123456;
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(amountToSwap),
            sqrtPriceLimitX96: SQRT_PRICE_1_2
        });
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        vm.snapshotGasLastCall("swap CA custom curve + swap noop");

        // the custom curve hook is 1-1 linear
        assertEq(currency0.balanceOf(address(this)), balanceBefore0 - amountToSwap, "amount 0");
        assertEq(currency1.balanceOf(address(this)), balanceBefore1 + amountToSwap, "amount 1");
    }

    function test_swap_beforeSwapNoOpsSwap_exactOutput() public {
        _setUpCustomCurvePool();

        // add liquidity by sending tokens straight into the contract
        key.currency0.transfer(hook, 10e18);
        key.currency1.transfer(hook, 10e18);

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));

        uint256 amountToSwap = 123456;
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(amountToSwap),
            sqrtPriceLimitX96: SQRT_PRICE_1_2
        });
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        // the custom curve hook is 1-1 linear
        assertEq(currency0.balanceOf(address(this)), balanceBefore0 - amountToSwap, "amount 0");
        assertEq(currency1.balanceOf(address(this)), balanceBefore1 + amountToSwap, "amount 1");
    }

    // maximum available liquidity in each direction for the pool in test_fuzz_swap_beforeSwap_returnsDeltaSpecified
    int128 maxPossibleIn_fuzz_test = -6018336102428409;
    int128 maxPossibleOut_fuzz_test = 5981737760509662;

    function test_fuzz_swap_beforeSwap_returnsDeltaSpecified(
        int128 hookDeltaSpecified,
        int256 amountSpecified,
        bool zeroForOne
    ) public {
        // ------------------------ SETUP ------------------------
        Currency specifiedCurrency;
        bool isExactIn;
        _setUpDeltaReturnFuzzPool();

        // initialize the pool and give the hook tokens to pay into swaps
        key.currency0.transfer(hook, type(uint128).max);
        key.currency1.transfer(hook, type(uint128).max);

        // bound amount specified to be a fair amount less than the amount of liquidity we have
        amountSpecified = int128(bound(amountSpecified, -3e11, 3e11));
        isExactIn = amountSpecified < 0;
        specifiedCurrency = (isExactIn == zeroForOne) ? key.currency0 : key.currency1;

        // bound delta in specified to not take more than the reserves available, nor be the minimum int to
        // stop the hook reverting on take/settle
        uint128 reservesOfSpecified = uint128(specifiedCurrency.balanceOf(address(manager)));
        hookDeltaSpecified = int128(bound(hookDeltaSpecified, type(int128).min + 1, int128(reservesOfSpecified)));
        DeltaReturningHook(hook).setDeltaSpecified(hookDeltaSpecified);

        // setup swap variables
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: (zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT)
        });

        // ------------------------ FUZZING CASES ------------------------
        // with an amount specified of 0: the trade reverts
        if (amountSpecified == 0) {
            vm.expectRevert(IPoolManager.SwapAmountCannotBeZero.selector);
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);

            // trade is exact input of n:, the hook cannot TAKE (+ve hookDeltaSpecified) more than n in input
            // otherwise the user would have to send more than n in input
        } else if (isExactIn && (hookDeltaSpecified > -amountSpecified)) {
            vm.expectRevert(Hooks.HookDeltaExceedsSwapAmount.selector);
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);

            // exact output of n: the hook cannot GIVE (-ve hookDeltaSpecified) more than n in output
            // otherwise the user would receive more than n in output
        } else if (!isExactIn && (amountSpecified < -hookDeltaSpecified)) {
            vm.expectRevert(Hooks.HookDeltaExceedsSwapAmount.selector);
            swapRouter.swap(key, params, testSettings, ZERO_BYTES);

            // successful swaps !
        } else {
            uint256 balanceThisBefore = specifiedCurrency.balanceOf(address(this));
            uint256 balanceHookBefore = specifiedCurrency.balanceOf(hook);
            uint256 balanceManagerBefore = specifiedCurrency.balanceOf(address(manager));

            BalanceDelta delta = swapRouter.swap(key, params, testSettings, ZERO_BYTES);
            int128 deltaSpecified = (zeroForOne == isExactIn) ? delta.amount0() : delta.amount1();

            // in all cases the hook gets what they took, and the user gets the swap's output delta (checked more below)
            assertEq(
                balanceHookBefore.toInt256() + hookDeltaSpecified,
                specifiedCurrency.balanceOf(hook).toInt256(),
                "hook balance change incorrect"
            );
            assertEq(
                balanceThisBefore.toInt256() + deltaSpecified,
                specifiedCurrency.balanceOf(address(this)).toInt256(),
                "swapper balance change incorrect"
            );

            // exact input, where there arent enough input reserves available to pay swap and hook
            // note: all 3 values are negative, so we use <
            if (isExactIn && (hookDeltaSpecified + amountSpecified < maxPossibleIn_fuzz_test)) {
                // the hook will have taken hookDeltaSpecified of the maxPossibleIn
                assertEq(deltaSpecified, maxPossibleIn_fuzz_test - hookDeltaSpecified, "deltaSpecified exact input");
                // the manager received all possible input tokens
                assertEq(
                    balanceManagerBefore.toInt256() - maxPossibleIn_fuzz_test,
                    specifiedCurrency.balanceOf(address(manager)).toInt256(),
                    "manager balance change exact input"
                );

                // exact output, where there isn't enough output reserves available to pay swap and hook
            } else if (!isExactIn && (hookDeltaSpecified + amountSpecified > maxPossibleOut_fuzz_test)) {
                // the hook will have taken hookDeltaSpecified of the maxPossibleOut
                assertEq(deltaSpecified, maxPossibleOut_fuzz_test - hookDeltaSpecified, "deltaSpecified exact output");
                // the manager sent out all possible output tokens
                assertEq(
                    balanceManagerBefore.toInt256() - maxPossibleOut_fuzz_test,
                    specifiedCurrency.balanceOf(address(manager)).toInt256(),
                    "manager balance change exact output"
                );

                // enough reserves were available, so the user got what they desired
            } else {
                assertEq(deltaSpecified, amountSpecified, "deltaSpecified not amountSpecified");
                assertEq(
                    balanceManagerBefore.toInt256() - amountSpecified - hookDeltaSpecified,
                    specifiedCurrency.balanceOf(address(manager)).toInt256(),
                    "manager balance change not"
                );
            }
        }
    }

    // ------------------------ MODIFY LIQUIDITY ------------------------

    function test_addLiquidity_withFeeTakingHook() public {
        _setUpFeeTakingPool();

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));
        uint256 hookBalanceBefore0 = currency0.balanceOf(hook);
        uint256 hookBalanceBefore1 = currency1.balanceOf(hook);
        uint256 managerBalanceBefore0 = currency0.balanceOf(address(manager));
        uint256 managerBalanceBefore1 = currency1.balanceOf(address(manager));
        // console2.log(address(key.hooks));
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        vm.snapshotGasLastCall("addLiquidity CA fee");

        uint256 hookGain0 = currency0.balanceOf(hook) - hookBalanceBefore0;
        uint256 hookGain1 = currency1.balanceOf(hook) - hookBalanceBefore1;
        uint256 thisLoss0 = balanceBefore0 - currency0.balanceOf(address(this));
        uint256 thisLoss1 = balanceBefore1 - currency1.balanceOf(address(this));
        uint256 managerGain0 = currency0.balanceOf(address(manager)) - managerBalanceBefore0;
        uint256 managerGain1 = currency1.balanceOf(address(manager)) - managerBalanceBefore1;

        // Assert that the hook got 5.43% of the added liquidity
        assertEq(hookGain0, managerGain0 * 543 / 10000, "hook amount 0");
        assertEq(hookGain1, managerGain1 * 543 / 10000, "hook amount 1");
        assertEq(thisLoss0 - hookGain0, managerGain0, "manager amount 0");
        assertEq(thisLoss1 - hookGain1, managerGain1, "manager amount 1");
    }

    function test_removeLiquidity_withFeeTakingHook() public {
        _setUpFeeTakingPool();

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));
        uint256 hookBalanceBefore0 = currency0.balanceOf(hook);
        uint256 hookBalanceBefore1 = currency1.balanceOf(hook);
        uint256 managerBalanceBefore0 = currency0.balanceOf(address(manager));
        uint256 managerBalanceBefore1 = currency1.balanceOf(address(manager));

        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        vm.snapshotGasLastCall("removeLiquidity CA fee");

        uint256 hookGain0 = currency0.balanceOf(hook) - hookBalanceBefore0;
        uint256 hookGain1 = currency1.balanceOf(hook) - hookBalanceBefore1;
        uint256 thisGain0 = currency0.balanceOf(address(this)) - balanceBefore0;
        uint256 thisGain1 = currency1.balanceOf(address(this)) - balanceBefore1;
        uint256 managerLoss0 = managerBalanceBefore0 - currency0.balanceOf(address(manager));
        uint256 managerLoss1 = managerBalanceBefore1 - currency1.balanceOf(address(manager));

        // Assert that the hook got 5.43% of the withdrawn liquidity
        assertEq(hookGain0, managerLoss0 * 543 / 10000, "hook amount 0");
        assertEq(hookGain1, managerLoss1 * 543 / 10000, "hook amount 1");
        assertEq(thisGain0 + hookGain0, managerLoss0, "manager amount 0");
        assertEq(thisGain1 + hookGain1, managerLoss1, "manager amount 1");
    }

    function test_fuzz_addLiquidity_withLPFeeTakingHook(uint128 feeRevenue0, uint128 feeRevenue1) public {
        feeRevenue0 = uint128(bound(feeRevenue0, 0, type(uint128).max / 2));
        feeRevenue1 = uint128(bound(feeRevenue1, 0, type(uint128).max / 2));
        _setUpLPFeeTakingPool(); // creates liquidity as part of setup

        // donate to generate fee revenue
        donateRouter.donate(key, feeRevenue0, feeRevenue1, ZERO_BYTES);

        uint256 hookBalanceBefore0 = currency0.balanceOf(hook);
        uint256 hookBalanceBefore1 = currency1.balanceOf(hook);

        // add liquidity again to trigger the hook, which should take the fee revenue
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);

        uint256 hookGain0 = currency0.balanceOf(hook) - hookBalanceBefore0;
        uint256 hookGain1 = currency1.balanceOf(hook) - hookBalanceBefore1;

        // Assert that the hook took ALL of the fee revenue, minus 1 wei of imprecision
        assertApproxEqAbs(hookGain0, feeRevenue0, 1 wei);
        assertApproxEqAbs(hookGain1, feeRevenue1, 1 wei);
        assertTrue(hookGain0 <= feeRevenue0);
        assertTrue(hookGain1 <= feeRevenue1);
    }

    function test_fuzz_removeLiquidity_withLPFeeTakingHook(uint128 feeRevenue0, uint128 feeRevenue1) public {
        // test fails when fee revenue approaches int128.max because PoolManager is limited by (principal + fees)
        feeRevenue0 = uint128(bound(feeRevenue0, 0, type(uint128).max / 3));
        feeRevenue1 = uint128(bound(feeRevenue1, 0, type(uint128).max / 3));
        _setUpLPFeeTakingPool(); // creates liquidity as part of setup

        // donate to generate fee revenue
        donateRouter.donate(key, feeRevenue0, feeRevenue1, ZERO_BYTES);

        uint256 balanceBefore0 = currency0.balanceOf(address(this));
        uint256 balanceBefore1 = currency1.balanceOf(address(this));
        uint256 hookBalanceBefore0 = currency0.balanceOf(hook);
        uint256 hookBalanceBefore1 = currency1.balanceOf(hook);
        uint256 managerBalanceBefore0 = currency0.balanceOf(address(manager));
        uint256 managerBalanceBefore1 = currency1.balanceOf(address(manager));

        // remove liquidity to trigger the hook, which should take the fee revenue
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);

        uint256 hookGain0 = currency0.balanceOf(hook) - hookBalanceBefore0;
        uint256 hookGain1 = currency1.balanceOf(hook) - hookBalanceBefore1;
        uint256 thisGain0 = currency0.balanceOf(address(this)) - balanceBefore0;
        uint256 thisGain1 = currency1.balanceOf(address(this)) - balanceBefore1;
        uint256 managerLoss0 = managerBalanceBefore0 - currency0.balanceOf(address(manager));
        uint256 managerLoss1 = managerBalanceBefore1 - currency1.balanceOf(address(manager));

        // Assert that the hook took ALL of the fee revenue, minus 1 wei of imprecision
        assertApproxEqAbs(hookGain0, feeRevenue0, 1 wei);
        assertApproxEqAbs(hookGain1, feeRevenue1, 1 wei);
        assertTrue(hookGain0 <= feeRevenue0);
        assertTrue(hookGain1 <= feeRevenue1);
        assertEq(thisGain0 + hookGain0, managerLoss0, "manager amount 0");
        assertEq(thisGain1 + hookGain1, managerLoss1, "manager amount 1");
    }
}
