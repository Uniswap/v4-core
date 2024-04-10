// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "../../src/types/Currency.sol";
import {PoolSwapTest} from "../../src/test/PoolSwapTest.sol";
import {Deployers} from "../utils/Deployers.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Pool} from "../../src/libraries/Pool.sol";
import {TickBitmap} from "../../src/libraries/TickBitmap.sol";
import {FixedPoint128} from "../../src/libraries/FixedPoint128.sol";

import {PoolManager} from "../../src/PoolManager.sol";

import {PoolStateLibrary} from "../../src/libraries/PoolStateLibrary.sol";

contract PoolStateLibraryTest is Test, Deployers {
    using FixedPointMathLib for uint256;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    PoolId poolId;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();
        (currency0, currency1) = Deployers.deployMintAndApprove2Currencies();

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(address(0x0)));
        poolId = key.toId();
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_getSlot0() public {
        // create liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-60, 60, 10_000 ether), ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-600, 600, 10_000 ether), ZERO_BYTES
        );

        // swap to create fees, crossing a tick
        uint256 swapAmount = 100 ether;
        swap(key, true, -int256(swapAmount), ZERO_BYTES);
        (, int24 currentTick,,) = manager.getSlot0(poolId);
        assertEq(currentTick, -139);

        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 swapFee) =
            PoolStateLibrary.getSlot0(manager, poolId);

        (uint160 sqrtPriceX96_, int24 tick_, uint24 protocolFee_, uint24 swapFee_) = manager.getSlot0(poolId);

        assertEq(sqrtPriceX96, sqrtPriceX96_);
        assertEq(tick, tick_);
        assertEq(tick, -139);
        assertEq(protocolFee, 0);
        assertEq(protocolFee, protocolFee_);
        assertEq(swapFee, 3000);
        assertEq(swapFee, swapFee_);
    }

    // function test_getSlot0_fuzz(
    //     int24 tickLower,
    //     int24 tickUpper,
    //     uint128 liquidityDeltaA,
    //     uint256 swapAmount,
    //     bool zeroForOne
    // ) public {
    //     BalanceDelta delta;
    //     (tickLower, tickUpper, liquidityDeltaA, delta) =
    //         createFuzzyLiquidity(modifyLiquidityRouter, key, tickLower, tickUpper, liquidityDeltaA, ZERO_BYTES);

    //     // assume swap amount is material, and less than 1/5th of the liquidity
    //     vm.assume(0.0000000001 ether < swapAmount);
    //     vm.assume(
    //         swapAmount < uint256(int256(-delta.amount0())) / 5 && swapAmount < uint256(int256(-delta.amount1())) / 5
    //     );
    //     swap(key, zeroForOne, -int256(swapAmount), ZERO_BYTES);

    //     (uint160 sqrtPriceX96, int24 tick, uint16 protocolFee, uint24 swapFee) =
    //         PoolStateLibrary.getSlot0(manager, poolId);

    //     (uint160 sqrtPriceX96_, int24 tick_, uint16 protocolFee_, uint24 _swapFee) = manager.getSlot0(poolId);

    //     assertEq(sqrtPriceX96, sqrtPriceX96_);
    //     assertEq(tick, tick_);
    //     assertEq(protocolFee, 0);
    //     assertEq(protocolFee, protocolFee_);
    //     assertEq(swapFee, 3000);
    //     assertEq(swapFee, _swapFee);
    // }

    function test_getTickLiquidity() public {
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-60, 60, 10 ether), ZERO_BYTES);

        (uint128 liquidityGrossLower, int128 liquidityNetLower) =
            PoolStateLibrary.getTickLiquidity(manager, poolId, -60);
        assertEq(liquidityGrossLower, 10 ether);
        assertEq(liquidityNetLower, 10 ether);

        (uint128 liquidityGrossUpper, int128 liquidityNetUpper) = PoolStateLibrary.getTickLiquidity(manager, poolId, 60);
        assertEq(liquidityGrossUpper, 10 ether);
        assertEq(liquidityNetUpper, -10 ether);
    }

    // function test_getTickLiquidity_fuzz(
    //     int24 tickLowerA,
    //     int24 tickUpperA,
    //     uint128 liquidityDeltaA,
    //     int24 tickLowerB,
    //     int24 tickUpperB,
    //     uint128 liquidityDeltaB
    // ) public {
    //     (tickLowerA, tickUpperA, liquidityDeltaA,) =
    //         createFuzzyLiquidity(modifyLiquidityRouter, key, tickLowerA, tickUpperA, liquidityDeltaA, ZERO_BYTES);
    //     (tickLowerB, tickUpperB, liquidityDeltaB,) =
    //         createFuzzyLiquidity(modifyLiquidityRouter, key, tickLowerB, tickUpperB, liquidityDeltaB, ZERO_BYTES);

    //     (uint128 liquidityGrossLowerA, int128 liquidityNetLowerA) =
    //         PoolStateLibrary.getTickLiquidity(manager, poolId, tickLowerA);
    //     (uint128 liquidityGrossLowerB, int128 liquidityNetLowerB) =
    //         PoolStateLibrary.getTickLiquidity(manager, poolId, tickLowerB);
    //     (uint256 liquidityGrossUpperA, int256 liquidityNetUpperA) =
    //         PoolStateLibrary.getTickLiquidity(manager, poolId, tickUpperA);
    //     (uint256 liquidityGrossUpperB, int256 liquidityNetUpperB) =
    //         PoolStateLibrary.getTickLiquidity(manager, poolId, tickUpperB);

    //     // when tick lower is shared between two positions, the gross liquidity is the sum
    //     if (tickLowerA == tickLowerB || tickLowerA == tickUpperB) {
    //         assertEq(liquidityGrossLowerA, liquidityDeltaA + liquidityDeltaB);

    //         // when tick lower is shared with an upper tick, the net liquidity is the difference
    //         (tickLowerA == tickLowerB)
    //             ? assertEq(liquidityNetLowerA, int128(liquidityDeltaA + liquidityDeltaB), "B")
    //             : assertApproxEqAbs(liquidityNetLowerA, int128(liquidityDeltaA) - int128(liquidityDeltaB), 1 wei);
    //     } else {
    //         assertEq(liquidityGrossLowerA, liquidityDeltaA, "C");
    //         assertEq(liquidityNetLowerA, int128(liquidityDeltaA), "D");
    //     }

    //     if (tickUpperA == tickLowerB || tickUpperA == tickUpperB) {
    //         assertEq(liquidityGrossUpperA, liquidityDeltaA + liquidityDeltaB, "C");
    //         (tickUpperA == tickUpperB)
    //             ? assertEq(liquidityNetUpperA, -int128(liquidityDeltaA + liquidityDeltaB), "D")
    //             : assertApproxEqAbs(liquidityNetUpperA, int128(liquidityDeltaB) - int128(liquidityDeltaA), 2 wei);
    //     } else {
    //         assertEq(liquidityGrossUpperA, liquidityDeltaA, "E");
    //         assertEq(liquidityNetUpperA, -int128(liquidityDeltaA), "F");
    //     }

    //     if (tickLowerB == tickLowerA || tickLowerB == tickUpperA) {
    //         assertEq(liquidityGrossLowerB, liquidityDeltaA + liquidityDeltaB, "G");
    //         (tickLowerB == tickLowerA)
    //             ? assertEq(liquidityNetLowerB, int128(liquidityDeltaA + liquidityDeltaB), "H")
    //             : assertApproxEqAbs(liquidityNetLowerB, int128(liquidityDeltaB) - int128(liquidityDeltaA), 1 wei);
    //     } else {
    //         assertEq(liquidityGrossLowerB, liquidityDeltaB, "I");
    //         assertEq(liquidityNetLowerB, int128(liquidityDeltaB), "J");
    //     }

    //     if (tickUpperB == tickLowerA || tickUpperB == tickUpperA) {
    //         assertEq(liquidityGrossUpperB, liquidityDeltaA + liquidityDeltaB, "K");
    //         (tickUpperB == tickUpperA)
    //             ? assertEq(liquidityNetUpperB, -int128(liquidityDeltaA + liquidityDeltaB), "L")
    //             : assertApproxEqAbs(liquidityNetUpperB, int128(liquidityDeltaA) - int128(liquidityDeltaB), 2 wei);
    //     } else {
    //         assertEq(liquidityGrossUpperB, liquidityDeltaB, "M");
    //         assertEq(liquidityNetUpperB, -int128(liquidityDeltaB), "N");
    //     }
    // }

    function test_getFeeGrowthGlobal0() public {
        // create liquidity
        uint256 liquidity = 10_000 ether;
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-60, 60, int256(liquidity)), ZERO_BYTES
        );

        (uint256 feeGrowthGlobal0, uint256 feeGrowthGlobal1) = PoolStateLibrary.getFeeGrowthGlobal(manager, poolId);
        assertEq(feeGrowthGlobal0, 0);
        assertEq(feeGrowthGlobal1, 0);

        // swap to create fees on the output token (currency1)
        uint256 swapAmount = 10 ether;
        swap(key, true, -int256(swapAmount), ZERO_BYTES);

        (feeGrowthGlobal0, feeGrowthGlobal1) = PoolStateLibrary.getFeeGrowthGlobal(manager, poolId);

        uint256 feeGrowthGlobalCalc = swapAmount.mulWadDown(0.003e18).mulDivDown(FixedPoint128.Q128, liquidity);
        assertEq(feeGrowthGlobal0, feeGrowthGlobalCalc);
        assertEq(feeGrowthGlobal1, 0);
    }

    function test_getFeeGrowthGlobal1() public {
        // create liquidity
        uint256 liquidity = 10_000 ether;
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-60, 60, int256(liquidity)), ZERO_BYTES
        );

        (uint256 feeGrowthGlobal0, uint256 feeGrowthGlobal1) = PoolStateLibrary.getFeeGrowthGlobal(manager, poolId);
        assertEq(feeGrowthGlobal0, 0);
        assertEq(feeGrowthGlobal1, 0);

        // swap to create fees on the input token (currency0)
        uint256 swapAmount = 10 ether;
        swap(key, false, -int256(swapAmount), ZERO_BYTES);

        (feeGrowthGlobal0, feeGrowthGlobal1) = PoolStateLibrary.getFeeGrowthGlobal(manager, poolId);

        assertEq(feeGrowthGlobal0, 0);
        uint256 feeGrowthGlobalCalc = swapAmount.mulWadDown(0.003e18).mulDivDown(FixedPoint128.Q128, liquidity);
        assertEq(feeGrowthGlobal1, feeGrowthGlobalCalc);
    }

    function test_getLiquidity() public {
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-60, 60, 10 ether), ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-120, 120, 10 ether), ZERO_BYTES);

        uint128 liquidity = PoolStateLibrary.getLiquidity(manager, poolId);
        assertEq(liquidity, 20 ether);
    }

    // function test_getLiquidity_fuzz(uint128 liquidityDelta) public {
    //     vm.assume(liquidityDelta != 0);
    //     vm.assume(liquidityDelta < Pool.tickSpacingToMaxLiquidityPerTick(key.tickSpacing));
    //     modifyLiquidityRouter.modifyLiquidity(
    //         key,
    //         IPoolManager.ModifyLiquidityParams(
    //             TickMath.minUsableTick(60), TickMath.maxUsableTick(60), int256(uint256(liquidityDelta))
    //         ),
    //         ZERO_BYTES
    //     );

    //     uint128 liquidity = PoolStateLibrary.getLiquidity(manager, poolId);
    //     assertEq(liquidity, liquidityDelta);
    // }

    function test_getTickBitmap() public {
        int24 tickLower = -300;
        int24 tickUpper = 300;
        // create liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(tickLower, tickUpper, 10_000 ether), ZERO_BYTES
        );

        (int16 wordPos, uint8 bitPos) = TickBitmap.position(tickLower / key.tickSpacing);
        uint256 tickBitmap = PoolStateLibrary.getTickBitmap(manager, poolId, wordPos);
        assertNotEq(tickBitmap, 0);
        assertEq(tickBitmap, 1 << bitPos);

        (wordPos, bitPos) = TickBitmap.position(tickUpper / key.tickSpacing);
        tickBitmap = PoolStateLibrary.getTickBitmap(manager, poolId, wordPos);
        assertNotEq(tickBitmap, 0);
        assertEq(tickBitmap, 1 << bitPos);
    }

    // function test_getTickBitmap_fuzz(int24 tickLower, int24 tickUpper, uint128 liquidityDelta) public {
    //     // TODO: if theres neighboring ticks, the bitmap is not a shifted bit
    //     (tickLower, tickUpper, liquidityDelta,) =
    //         createFuzzyLiquidity(modifyLiquidityRouter, key, tickLower, tickUpper, liquidityDelta, ZERO_BYTES);

    //     (int16 wordPos, uint8 bitPos) = TickBitmap.position(tickLower / key.tickSpacing);
    //     (int16 wordPosUpper, uint8 bitPosUpper) = TickBitmap.position(tickUpper / key.tickSpacing);

    //     uint256 tickBitmap = PoolStateLibrary.getTickBitmap(manager, poolId, wordPos);
    //     assertNotEq(tickBitmap, 0);

    //     // in fuzz tests, the tickLower and tickUpper might exist on the same word
    //     if (wordPos == wordPosUpper) {
    //         assertEq(tickBitmap, (1 << bitPos) | (1 << bitPosUpper));
    //     } else {
    //         assertEq(tickBitmap, 1 << bitPos);
    //     }
    // }

    function test_getPositionInfo() public {
        // create liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-60, 60, 10_000 ether), ZERO_BYTES
        );

        // swap to create fees, crossing a tick
        uint256 swapAmount = 10 ether;
        swap(key, true, -int256(swapAmount), ZERO_BYTES);
        (, int24 currentTick,,) = manager.getSlot0(poolId);
        assertNotEq(currentTick, 0);

        // poke the LP so that fees are updated
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-60, 60, 0), ZERO_BYTES);

        bytes32 positionId = keccak256(abi.encodePacked(address(modifyLiquidityRouter), int24(-60), int24(60)));

        (uint128 liquidity, uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            PoolStateLibrary.getPositionInfo(manager, poolId, positionId);

        assertEq(liquidity, 10_000 ether);

        assertNotEq(feeGrowthInside0X128, 0);
        assertEq(feeGrowthInside1X128, 0);
    }

    // function test_getPositionInfo_fuzz(
    //     int24 tickLower,
    //     int24 tickUpper,
    //     uint128 liquidityDelta,
    //     uint256 swapAmount,
    //     bool zeroForOne
    // ) public {
    //     BalanceDelta delta;
    //     (tickLower, tickUpper, liquidityDelta, delta) =
    //         createFuzzyLiquidity(modifyLiquidityRouter, key, tickLower, tickUpper, liquidityDelta, ZERO_BYTES);

    //     // assume swap amount is material, and less than 1/5th of the liquidity
    //     vm.assume(0.0000000001 ether < swapAmount);
    //     vm.assume(
    //         swapAmount < uint256(int256(-delta.amount0())) / 5 && swapAmount < uint256(int256(-delta.amount1())) / 5
    //     );
    //     swap(key, zeroForOne, -int256(swapAmount), ZERO_BYTES);

    //     // poke the LP so that fees are updated
    //     modifyLiquidityRouter.modifyLiquidity(
    //         key, IPoolManager.ModifyLiquidityParams(tickLower, tickUpper, 0), ZERO_BYTES
    //     );

    //     bytes32 positionId = keccak256(abi.encodePacked(address(modifyLiquidityRouter), tickLower, tickUpper));

    //     (uint128 liquidity, uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
    //         PoolStateLibrary.getPositionInfo(manager, poolId, positionId);

    //     assertEq(liquidity, liquidityDelta);
    //     if (zeroForOne) {
    //         assertNotEq(feeGrowthInside0X128, 0);
    //         assertEq(feeGrowthInside1X128, 0);
    //     } else {
    //         assertEq(feeGrowthInside0X128, 0);
    //         assertNotEq(feeGrowthInside1X128, 0);
    //     }
    // }

    // a bit annoying to fuzz since you need to get feeGrowth outside of a tick
    function test_getTickFeeGrowthOutside() public {
        // create liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-60, 60, 10_000 ether), ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-600, 600, 10_000 ether), ZERO_BYTES
        );

        // swap to create fees, crossing a tick
        uint256 swapAmount = 100 ether;
        swap(key, true, -int256(swapAmount), ZERO_BYTES);
        (, int24 currentTick,,) = manager.getSlot0(poolId);
        assertEq(currentTick, -139);

        int24 tick = -60;
        (uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128) =
            PoolStateLibrary.getTickFeeGrowthOutside(manager, poolId, tick);

        //(uint256 outside0, uint256 outside1) = PoolManager(payable(manager)).getTickFeeGrowthOutside(poolId, tick);

        assertNotEq(feeGrowthOutside0X128, 0);
        assertEq(feeGrowthOutside1X128, 0);
        // assertEq(feeGrowthOutside0X128, outside0);
        // assertEq(feeGrowthOutside1X128, outside1);
    }

    // also hard to fuzz because of feeGrowthOutside
    function test_getTickInfo() public {
        // create liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-60, 60, 10_000 ether), ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-600, 600, 10_000 ether), ZERO_BYTES
        );

        // swap to create fees, crossing a tick
        uint256 swapAmount = 100 ether;
        swap(key, true, -int256(swapAmount), ZERO_BYTES);
        (, int24 currentTick,,) = manager.getSlot0(poolId);
        assertEq(currentTick, -139);

        int24 tick = -60;
        (uint128 liquidityGross, int128 liquidityNet, uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128) =
            PoolStateLibrary.getTickInfo(manager, poolId, tick);

        (uint128 liquidityGross_, int128 liquidityNet_) = PoolStateLibrary.getTickLiquidity(manager, poolId, tick);
        (uint256 feeGrowthOutside0X128_, uint256 feeGrowthOutside1X128_) =
            PoolStateLibrary.getTickFeeGrowthOutside(manager, poolId, tick);

        assertEq(liquidityGross, 10_000 ether);
        assertEq(liquidityGross, liquidityGross_);
        assertEq(liquidityNet, liquidityNet_);

        assertNotEq(feeGrowthOutside0X128, 0);
        assertEq(feeGrowthOutside1X128, 0);
        assertEq(feeGrowthOutside0X128, feeGrowthOutside0X128_);
        assertEq(feeGrowthOutside1X128, feeGrowthOutside1X128_);
    }

    function test_getFeeGrowthInside() public {
        // create liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-60, 60, 10_000 ether), ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-600, 600, 10_000 ether), ZERO_BYTES
        );

        // swap to create fees, crossing a tick
        uint256 swapAmount = 100 ether;
        swap(key, true, -int256(swapAmount), ZERO_BYTES);
        (, int24 currentTick,,) = manager.getSlot0(poolId);
        assertEq(currentTick, -139);

        // calculated live
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            PoolStateLibrary.getFeeGrowthInside(manager, poolId, -60, 60);

        // poke the LP so that fees are updated
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-60, 60, 0), ZERO_BYTES);

        bytes32 positionId = keccak256(abi.encodePacked(address(modifyLiquidityRouter), int24(-60), int24(60)));

        (, uint256 feeGrowthInside0X128_, uint256 feeGrowthInside1X128_) =
            PoolStateLibrary.getPositionInfo(manager, poolId, positionId);

        assertNotEq(feeGrowthInside0X128, 0);
        assertEq(feeGrowthInside0X128, feeGrowthInside0X128_);
        assertEq(feeGrowthInside1X128, feeGrowthInside1X128_);
    }

    // function test_getFeeGrowthInside_fuzz(int24 tickLower, int24 tickUpper, uint128 liquidityDelta, bool zeroForOne)
    //     public
    // {
    //     modifyLiquidityRouter.modifyLiquidity(
    //         key,
    //         IPoolManager.ModifyLiquidityParams(
    //             TickMath.minUsableTick(key.tickSpacing), TickMath.maxUsableTick(key.tickSpacing), 10_000 ether
    //         ),
    //         ZERO_BYTES
    //     );

    //     BalanceDelta delta;
    //     (tickLower, tickUpper, liquidityDelta, delta) =
    //         createFuzzyLiquidity(modifyLiquidityRouter, key, tickLower, tickUpper, liquidityDelta, ZERO_BYTES);
    //     vm.assume(delta.amount0() != 0);
    //     vm.assume(delta.amount1() != 0);

    //     swap(key, zeroForOne, -int256(100e18), ZERO_BYTES);

    //     // calculated live
    //     (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
    //         PoolStateLibrary.getFeeGrowthInside(manager, poolId, tickLower, tickUpper);

    //     // poke the LP so that fees are updated
    //     modifyLiquidityRouter.modifyLiquidity(
    //         key, IPoolManager.ModifyLiquidityParams(tickLower, tickUpper, 0), ZERO_BYTES
    //     );
    //     bytes32 positionId = keccak256(abi.encodePacked(address(modifyLiquidityRouter), tickLower, tickUpper));

    //     (, uint256 feeGrowthInside0X128_, uint256 feeGrowthInside1X128_) =
    //         PoolStateLibrary.getPositionInfo(manager, poolId, positionId);

    //     assertEq(feeGrowthInside0X128, feeGrowthInside0X128_);
    //     assertEq(feeGrowthInside1X128, feeGrowthInside1X128_);
    // }

    function test_getPositionLiquidity() public {
        // create liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key, IPoolManager.ModifyLiquidityParams(-60, 60, 10_000 ether), ZERO_BYTES
        );

        bytes32 positionId = keccak256(abi.encodePacked(address(modifyLiquidityRouter), int24(-60), int24(60)));

        uint128 liquidity = PoolStateLibrary.getPositionLiquidity(manager, poolId, positionId);

        assertEq(liquidity, 10_000 ether);
    }

    // function test_getPositionLiquidity_fuzz(
    //     int24 tickLowerA,
    //     int24 tickUpperA,
    //     uint128 liquidityDeltaA,
    //     int24 tickLowerB,
    //     int24 tickUpperB,
    //     uint128 liquidityDeltaB
    // ) public {
    //     (tickLowerA, tickUpperA, liquidityDeltaA,) =
    //         createFuzzyLiquidity(modifyLiquidityRouter, key, tickLowerA, tickUpperA, liquidityDeltaA, ZERO_BYTES);
    //     (tickLowerB, tickUpperB, liquidityDeltaB,) =
    //         createFuzzyLiquidity(modifyLiquidityRouter, key, tickLowerB, tickUpperB, liquidityDeltaB, ZERO_BYTES);

    //     vm.assume(tickLowerA != tickLowerB && tickUpperA != tickUpperB);

    //     bytes32 positionIdA = keccak256(abi.encodePacked(address(modifyLiquidityRouter), tickLowerA, tickUpperA));
    //     uint128 liquidityA = PoolStateLibrary.getPositionLiquidity(manager, poolId, positionIdA);
    //     assertEq(liquidityA, liquidityDeltaA);

    //     bytes32 positionIdB = keccak256(abi.encodePacked(address(modifyLiquidityRouter), tickLowerB, tickUpperB));
    //     uint128 liquidityB = PoolStateLibrary.getPositionLiquidity(manager, poolId, positionIdB);
    //     assertEq(liquidityB, liquidityDeltaB);
    // }
}
