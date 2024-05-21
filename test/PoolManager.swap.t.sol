// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {
    V3Helper,
    IUniswapV3Pool,
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback,
    FeeTiers,
    FeeTiersLib
} from "./utils/V3Helper.sol";
import {Deployers} from "./utils/Deployers.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {Fuzzers} from "../src/test/Fuzzers.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../src/types/BalanceDelta.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {SqrtPriceMath} from "../src/libraries/SqrtPriceMath.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";
import {LiquidityAmounts} from "./utils/LiquidityAmounts.sol";

abstract contract V3Fuzzer is V3Helper, Deployers, Fuzzers, IUniswapV3MintCallback, IUniswapV3SwapCallback {
    using CurrencyLibrary for Currency;
    using FeeTiersLib for FeeTiers;

    function setUp() public virtual override {
        super.setUp();
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
    }

    function addLiquidity(
        FeeTiers fee,
        int256 sqrtPriceX96seed,
        int24 lowerTickUnsanitized,
        int24 upperTickUnsanitized,
        uint128 amount0Unbound,
        uint128 amount1Unbound
    ) internal returns (IUniswapV3Pool v3Pool, PoolKey memory key_) {
        // init pools
        key_ = PoolKey(currency0, currency1, fee.amount(), fee.tickSpacing(), IHooks(address(0)));

        uint160 sqrtPriceX96 = createRandomSqrtPriceX96(key_, sqrtPriceX96seed);

        IPoolManager.ModifyLiquidityParams memory v4LiquidityParams = IPoolManager.ModifyLiquidityParams({
            tickLower: lowerTickUnsanitized,
            tickUpper: upperTickUnsanitized,
            liquidityDelta: 0,
            salt: 0
        });

        v4LiquidityParams =
            createFuzzyLiquidityParamsFromAmounts(key_, v4LiquidityParams, amount0Unbound, amount1Unbound, sqrtPriceX96);

        v3Pool =
            IUniswapV3Pool(v3Factory.createPool(Currency.unwrap(currency0), Currency.unwrap(currency1), fee.amount()));
        v3Pool.initialize(sqrtPriceX96);

        manager.initialize(key_, sqrtPriceX96, "");

        // add liquidity
        v3Pool.mint(
            address(this),
            v4LiquidityParams.tickLower,
            v4LiquidityParams.tickUpper,
            uint128(int128(v4LiquidityParams.liquidityDelta)),
            ""
        );
        modifyLiquidityRouter.modifyLiquidity(key_, v4LiquidityParams, "");
    }

    function swap(IUniswapV3Pool pool, PoolKey memory key_, bool zeroForOne, int256 amountSpecified)
        internal
        returns (int256 amount0Diff, int256 amount1Diff)
    {
        // v3 swap
        (int256 amount0Delta, int256 amount1Delta) =
            pool.swap(address(this), zeroForOne, amountSpecified, zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT, "");
        // v4 swap
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified * -1, // invert because v3 and v4 swaps use inverted signs
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        BalanceDelta delta = swapRouter.swap(key_, swapParams, testSettings, "");

        // because signs for v3 and v4 swaps are inverted, add values up to get the difference
        amount0Diff = amount0Delta + delta.amount0();
        amount1Diff = amount1Delta + delta.amount1();
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        currency0.transfer(msg.sender, amount0Owed);
        currency1.transfer(msg.sender, amount1Owed);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (amount0Delta > 0) currency0.transfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) currency1.transfer(msg.sender, uint256(amount1Delta));
    }
}

contract V3SwapTests is V3Fuzzer {
    using SafeCast for *;

    function test_shouldSwapEqual(
        int24 lowerTickUnsanitized,
        int24 upperTickUnsanitized,
        uint128 amount0Unbound,
        uint128 amount1Unbound,
        int256 sqrtPriceX96seed
    ) public {
        (IUniswapV3Pool pool, PoolKey memory key_) = addLiquidity(
            FeeTiers.FEE_3000,
            sqrtPriceX96seed,
            lowerTickUnsanitized,
            upperTickUnsanitized,
            amount0Unbound,
            amount1Unbound
        );
        (int256 amount0Diff, int256 amount1Diff) = swap(pool, key_, true, 100);
        assertEq(amount0Diff, 0);
        assertEq(amount1Diff, 0);
    }

    function test_shouldCalculateCorrectLiquidityDelta(
        int128 liquidityDelta,
        int24 tick,
        int24 tickLowerUnsanitized,
        int24 tickUpperUnsanitized
    ) public pure {
        tick = int24(bound(int256(tick), TickMath.minUsableTick(60), TickMath.maxUsableTick(60))) / 60 * 60;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        (int24 tickLower, int24 tickUpper) = boundTicks(tickLowerUnsanitized, tickUpperUnsanitized, 60);
        int128 amount0Delta;
        int128 amount1Delta;
        console2.log("tick:", tick);
        console2.log("tickLower:", tickLower);
        console2.log("tickUpper:", tickUpper);
        vm.assume(liquidityDelta > 0);
        console2.log("liquidityDelta:", liquidityDelta);
        if (tick < tickLower) {
            amount0Delta = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidityDelta
            ).toInt128();
        } else if (tick < tickUpper) {
            amount0Delta = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtPriceAtTick(tickLower), sqrtPriceX96, liquidityDelta
            ).toInt128();
            amount1Delta = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtPriceAtTick(tickLower), sqrtPriceX96, liquidityDelta
            ).toInt128();
        } else {
            amount1Delta = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidityDelta
            ).toInt128();
        }
        console2.log("amount0Delta:", amount0Delta);
        console2.log("amount1Delta:", amount1Delta);
        uint128 calculatedLiquidityDelta = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint256(int256(-amount0Delta)),
            uint256(int256(-amount1Delta))
        );
        console2.log("calculatedLiquidityDelta:", calculatedLiquidityDelta);
        assertEq(calculatedLiquidityDelta, uint128(liquidityDelta));
    }
}
