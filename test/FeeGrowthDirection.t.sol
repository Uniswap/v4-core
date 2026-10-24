// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "./utils/Deployers.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {PoolId} from "../src/types/PoolId.sol";
import {ModifyLiquidityParams} from "../src/types/PoolOperation.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {StateLibrary} from "../src/libraries/StateLibrary.sol";

/// @notice Asserts fee growth globals update on the correct token index after swaps.
/// @dev Closes https://github.com/Uniswap/v4-core/issues/606
contract FeeGrowthDirectionTest is Test, Deployers {
    using StateLibrary for IPoolManager;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
    }

    function test_feeGrowthDirection_zeroForOne_exactInput() public {
        (PoolKey memory poolKey,) =
            initPoolAndAddLiquidity(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
        PoolId poolId = poolKey.toId();

        (uint256 fg0, uint256 fg1) = manager.getFeeGrowthGlobals(poolId);
        assertEq(fg0, 0);
        assertEq(fg1, 0);

        swap(poolKey, true, -1 ether, ZERO_BYTES);

        (fg0, fg1) = manager.getFeeGrowthGlobals(poolId);
        assertGt(fg0, 0, "feeGrowthGlobal0 must increase for zeroForOne swap");
        assertEq(fg1, 0, "feeGrowthGlobal1 must remain 0 for zeroForOne swap");
    }

    function test_feeGrowthDirection_oneForZero_exactInput() public {
        (PoolKey memory poolKey,) =
            initPoolAndAddLiquidity(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
        PoolId poolId = poolKey.toId();

        swap(poolKey, false, -1 ether, ZERO_BYTES);

        (uint256 fg0, uint256 fg1) = manager.getFeeGrowthGlobals(poolId);
        assertGt(fg1, 0, "feeGrowthGlobal1 must increase for oneForZero swap");
        assertEq(fg0, 0, "feeGrowthGlobal0 must remain 0 for oneForZero swap");
    }

    function test_feeGrowthDirection_zeroForOne_exactOutput() public {
        (PoolKey memory poolKey,) =
            initPoolAndAddLiquidity(currency0, currency1, IHooks(address(0)), 500, SQRT_PRICE_1_1);
        PoolId poolId = poolKey.toId();

        swap(poolKey, true, -0.1 ether, ZERO_BYTES);

        (uint256 fg0, uint256 fg1) = manager.getFeeGrowthGlobals(poolId);
        assertGt(fg0, 0, "feeGrowthGlobal0 must increase for zeroForOne exact-output");
        assertEq(fg1, 0, "feeGrowthGlobal1 must remain 0 for zeroForOne exact-output");
    }

    function test_feeGrowthDirection_oneForZero_exactOutput() public {
        (PoolKey memory poolKey,) =
            initPoolAndAddLiquidity(currency0, currency1, IHooks(address(0)), 500, SQRT_PRICE_1_1);
        PoolId poolId = poolKey.toId();

        swap(poolKey, false, -0.1 ether, ZERO_BYTES);

        (uint256 fg0, uint256 fg1) = manager.getFeeGrowthGlobals(poolId);
        assertGt(fg1, 0, "feeGrowthGlobal1 must increase for oneForZero exact-output");
        assertEq(fg0, 0, "feeGrowthGlobal0 must remain 0 for oneForZero exact-output");
    }

    function test_feeGrowthDirection_bidirectional_independent() public {
        (PoolKey memory poolKey,) =
            initPoolAndAddLiquidity(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
        PoolId poolId = poolKey.toId();

        swap(poolKey, true, -1 ether, ZERO_BYTES);

        (uint256 fg0Mid, uint256 fg1Mid) = manager.getFeeGrowthGlobals(poolId);
        assertGt(fg0Mid, 0);
        assertEq(fg1Mid, 0);

        swap(poolKey, false, -1 ether, ZERO_BYTES);

        (uint256 fg0Final, uint256 fg1Final) = manager.getFeeGrowthGlobals(poolId);
        assertEq(fg0Final, fg0Mid, "feeGrowthGlobal0 unchanged after oneForZero swap");
        assertGt(fg1Final, 0, "feeGrowthGlobal1 must increase after oneForZero swap");
    }

    function test_feeGrowthDirection_withTickCrossing_zeroForOne() public {
        (PoolKey memory poolKey,) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
        PoolId poolId = poolKey.toId();

        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 10 ether, salt: 0}),
            ZERO_BYTES
        );
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10 ether, salt: 0}),
            ZERO_BYTES
        );

        swap(poolKey, true, -5 ether, ZERO_BYTES);

        (uint256 fg0, uint256 fg1) = manager.getFeeGrowthGlobals(poolId);
        assertGt(fg0, 0, "feeGrowthGlobal0 must increase after tick-crossing zeroForOne");
        assertEq(fg1, 0, "feeGrowthGlobal1 must remain 0 after tick-crossing zeroForOne");
    }

    function test_feeGrowthDirection_withTickCrossing_oneForZero() public {
        (PoolKey memory poolKey,) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
        PoolId poolId = poolKey.toId();

        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 10 ether, salt: 0}),
            ZERO_BYTES
        );
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10 ether, salt: 0}),
            ZERO_BYTES
        );

        swap(poolKey, false, -5 ether, ZERO_BYTES);

        (uint256 fg0, uint256 fg1) = manager.getFeeGrowthGlobals(poolId);
        assertEq(fg0, 0, "feeGrowthGlobal0 must remain 0 after tick-crossing oneForZero");
        assertGt(fg1, 0, "feeGrowthGlobal1 must increase after tick-crossing oneForZero");
    }

    function test_fuzz_feeGrowthDirection(bool zeroForOne, uint256 amountSeed) public {
        uint256 swapAmount = bound(amountSeed, 1e15, 1 ether);
        (PoolKey memory poolKey,) =
            initPoolAndAddLiquidity(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
        PoolId poolId = poolKey.toId();

        swap(poolKey, zeroForOne, -int256(swapAmount), ZERO_BYTES);

        (uint256 fg0, uint256 fg1) = manager.getFeeGrowthGlobals(poolId);

        if (zeroForOne) {
            assertGt(fg0, 0, "fuzz: feeGrowthGlobal0 should increase for zeroForOne");
            assertEq(fg1, 0, "fuzz: feeGrowthGlobal1 should remain 0 for zeroForOne");
        } else {
            assertEq(fg0, 0, "fuzz: feeGrowthGlobal0 should remain 0 for oneForZero");
            assertGt(fg1, 0, "fuzz: feeGrowthGlobal1 should increase for oneForZero");
        }
    }

    function test_feeGrowthDirection_native_zeroForOne() public {
        (PoolKey memory poolKey,) = initPoolAndAddLiquidityETH(
            CurrencyLibrary.ADDRESS_ZERO, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1, 10 ether
        );
        PoolId poolId = poolKey.toId();

        swapNativeInput(poolKey, true, -1 ether, ZERO_BYTES, 1 ether);

        (uint256 fg0, uint256 fg1) = manager.getFeeGrowthGlobals(poolId);
        assertGt(fg0, 0, "native: feeGrowthGlobal0 must increase for zeroForOne");
        assertEq(fg1, 0, "native: feeGrowthGlobal1 must remain 0 for zeroForOne");
    }

    function test_feeGrowthDirection_native_oneForZero() public {
        (PoolKey memory poolKey,) = initPoolAndAddLiquidityETH(
            CurrencyLibrary.ADDRESS_ZERO, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1, 10 ether
        );
        PoolId poolId = poolKey.toId();

        swap(poolKey, false, -1 ether, ZERO_BYTES);

        (uint256 fg0, uint256 fg1) = manager.getFeeGrowthGlobals(poolId);
        assertEq(fg0, 0, "native: feeGrowthGlobal0 must remain 0 for oneForZero");
        assertGt(fg1, 0, "native: feeGrowthGlobal1 must increase for oneForZero");
    }
}
