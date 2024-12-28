// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {V3Helper, IUniswapV3Pool, IUniswapV3MintCallback, IUniswapV3SwapCallback} from "./utils/V3Helper.sol";
import {Deployers} from "./utils/Deployers.sol";
import {Currency} from "../src/types/Currency.sol";
import {Fuzzers} from "../src/test/Fuzzers.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "../src/types/BalanceDelta.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {SqrtPriceMath} from "../src/libraries/SqrtPriceMath.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";
import {LiquidityAmounts} from "./utils/LiquidityAmounts.sol";

abstract contract V3Fuzzer is V3Helper, Deployers, Fuzzers, IUniswapV3MintCallback, IUniswapV3SwapCallback {
    function setUp() public virtual override {
        super.setUp();
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
    }

    function initPools(uint24 fee, int24 tickSpacing, int256 sqrtPriceX96seed)
        internal
        returns (IUniswapV3Pool v3Pool, PoolKey memory key_, uint160 sqrtPriceX96)
    {
        fee = uint24(bound(fee, 0, 999999));
        tickSpacing = int24(bound(tickSpacing, 1, 16383));
        // v3 pools don't allow overwriting existing fees, 500, 3000, 10000 are set by default in the constructor
        if (fee == 500) tickSpacing = 10;
        else if (fee == 3000) tickSpacing = 60;
        else if (fee == 10000) tickSpacing = 200;
        else v3Factory.enableFeeAmount(fee, tickSpacing);

        sqrtPriceX96 = createRandomSqrtPriceX96(tickSpacing, sqrtPriceX96seed);

        v3Pool = IUniswapV3Pool(v3Factory.createPool(Currency.unwrap(currency0), Currency.unwrap(currency1), fee));
        v3Pool.initialize(sqrtPriceX96);

        key_ = PoolKey(currency0, currency1, fee, tickSpacing, IHooks(address(0)));
        manager.initialize(key_, sqrtPriceX96);
    }

    function addLiquidity(
        IUniswapV3Pool v3Pool,
        PoolKey memory key_,
        uint160 sqrtPriceX96,
        int24 lowerTickUnsanitized,
        int24 upperTickUnsanitized,
        int256 liquidityDeltaUnbound,
        bool tight
    ) internal {
        IPoolManager.ModifyLiquidityParams memory v4LiquidityParams = IPoolManager.ModifyLiquidityParams({
            tickLower: lowerTickUnsanitized,
            tickUpper: upperTickUnsanitized,
            liquidityDelta: liquidityDeltaUnbound,
            salt: 0
        });

        v4LiquidityParams = tight
            ? createFuzzyLiquidityParamsWithTightBound(key_, v4LiquidityParams, sqrtPriceX96, 20)
            : createFuzzyLiquidityParams(key_, v4LiquidityParams, sqrtPriceX96);

        v3Pool.mint(
            address(this),
            v4LiquidityParams.tickLower,
            v4LiquidityParams.tickUpper,
            uint128(int128(v4LiquidityParams.liquidityDelta)),
            ""
        );

        modifyLiquidityRouter.modifyLiquidity(key_, v4LiquidityParams, "");
    }

    function swap(IUniswapV3Pool pool, PoolKey memory key_, bool zeroForOne, int128 amountSpecified)
        internal
        returns (int256 amount0Diff, int256 amount1Diff)
    {
        if (amountSpecified == 0) amountSpecified = 1;
        if (amountSpecified == type(int128).min) amountSpecified = type(int128).min + 1;
        // v3 swap
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            // invert amountSpecified because v3 swaps use inverted signs
            address(this),
            zeroForOne,
            amountSpecified * -1,
            zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT,
            ""
        );
        // v3 can handle bigger numbers than v4, so if we exceed int128, check that the next call reverts
        bool overflows = false;
        if (
            amount0Delta > type(int128).max || amount1Delta > type(int128).max || amount0Delta < type(int128).min
                || amount1Delta < type(int128).min
        ) {
            overflows = true;
        }
        // v4 swap
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        BalanceDelta delta;
        try swapRouter.swap(key_, swapParams, testSettings, "") returns (BalanceDelta delta_) {
            delta = delta_;
        } catch (bytes memory reason) {
            require(overflows, "v4 should not overflow");
            assertEq(bytes4(reason), SafeCast.SafeCastOverflow.selector);
            delta = toBalanceDelta(0, 0);
            amount0Delta = 0;
            amount1Delta = 0;
        }

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
    function test_shouldSwapEqual(
        uint24 feeSeed,
        int24 tickSpacingSeed,
        int24 lowerTickUnsanitized,
        int24 upperTickUnsanitized,
        int256 liquidityDeltaUnbound,
        int256 sqrtPriceX96seed,
        int128 swapAmount,
        bool zeroForOne
    ) public {
        (IUniswapV3Pool pool, PoolKey memory key_, uint160 sqrtPriceX96) =
            initPools(feeSeed, tickSpacingSeed, sqrtPriceX96seed);
        addLiquidity(pool, key_, sqrtPriceX96, lowerTickUnsanitized, upperTickUnsanitized, liquidityDeltaUnbound, false);
        (int256 amount0Diff, int256 amount1Diff) = swap(pool, key_, zeroForOne, swapAmount);
        assertEq(amount0Diff, 0);
        assertEq(amount1Diff, 0);
    }

    struct TightLiquidityParams {
        int24 lowerTickUnsanitized;
        int24 upperTickUnsanitized;
        int256 liquidityDeltaUnbound;
    }

    function test_shouldSwapEqualMultipleLP(
        uint24 feeSeed,
        int24 tickSpacingSeed,
        TightLiquidityParams[] memory liquidityParams,
        int256 sqrtPriceX96seed,
        int128 swapAmount,
        bool zeroForOne
    ) public {
        (IUniswapV3Pool pool, PoolKey memory key_, uint160 sqrtPriceX96) =
            initPools(feeSeed, tickSpacingSeed, sqrtPriceX96seed);
        for (uint256 i = 0; i < liquidityParams.length; ++i) {
            if (i == 20) break;
            addLiquidity(
                pool,
                key_,
                sqrtPriceX96,
                liquidityParams[i].lowerTickUnsanitized,
                liquidityParams[i].upperTickUnsanitized,
                liquidityParams[i].liquidityDeltaUnbound,
                true
            );
        }

        (int256 amount0Diff, int256 amount1Diff) = swap(pool, key_, zeroForOne, swapAmount);
        assertEq(amount0Diff, 0);
        assertEq(amount1Diff, 0);
    }
}
