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
        uint160 sqrtPriceX96,
        int24 lowerTickUnsanitized,
        int24 upperTickUnsanitized,
        int256 liquidityDeltaUnbound
    ) internal returns (IUniswapV3Pool v3Pool, PoolKey memory key_) {
        // init pools
        key_ = PoolKey(currency0, currency1, fee.amount(), fee.tickSpacing(), IHooks(address(0)));

        IPoolManager.ModifyLiquidityParams memory v4LiquidityParams = IPoolManager.ModifyLiquidityParams({
            tickLower: lowerTickUnsanitized,
            tickUpper: upperTickUnsanitized,
            liquidityDelta: liquidityDeltaUnbound,
            salt: 0
        });

        v4LiquidityParams = createFuzzyLiquidityParams(key_, v4LiquidityParams, sqrtPriceX96);

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
        vm.assume(amountSpecified != 0);
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
    using FeeTiersLib for FeeTiers;

    function test_shouldSwapEqual(
        int24 lowerTickUnsanitized,
        int24 upperTickUnsanitized,
        int256 liquidityDeltaUnbound,
        int256 sqrtPriceX96seed,
        bool zeroForOne
    ) public {
        uint160 sqrtPriceX96 = createRandomSqrtPriceX96(FeeTiers.FEE_3000.tickSpacing(), sqrtPriceX96seed);

        (IUniswapV3Pool pool, PoolKey memory key_) = addLiquidity(
            FeeTiers.FEE_3000, sqrtPriceX96, lowerTickUnsanitized, upperTickUnsanitized, liquidityDeltaUnbound
        );
        (int256 amount0Diff, int256 amount1Diff) = swap(pool, key_, zeroForOne, 1 ether);
        assertEq(amount0Diff, 0);
        assertEq(amount1Diff, 0);
    }
}
