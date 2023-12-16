// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Hooks} from "../../src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {PoolManager} from "../../src/PoolManager.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {FeeLibrary} from "../../src/libraries/FeeLibrary.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {Constants} from "../utils/Constants.sol";
import {SortTokens} from "./SortTokens.sol";
import {PoolModifyLiquidityTest} from "../../src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "../../src/test/PoolSwapTest.sol";
import {PoolInitializeTest} from "../../src/test/PoolInitializeTest.sol";
import {PoolDonateTest} from "../../src/test/PoolDonateTest.sol";
import {PoolTakeTest} from "../../src/test/PoolTakeTest.sol";
import {
    ProtocolFeeControllerTest,
    OutOfBoundsProtocolFeeControllerTest,
    RevertingProtocolFeeControllerTest,
    OverflowProtocolFeeControllerTest,
    InvalidReturnSizeProtocolFeeControllerTest
} from "../../src/test/ProtocolFeeControllerTest.sol";

contract Deployers {
    using FeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;

    // Helpful test constants
    bytes constant ZERO_BYTES = new bytes(0);
    uint160 constant SQRT_RATIO_1_1 = Constants.SQRT_RATIO_1_1;
    uint160 constant SQRT_RATIO_1_2 = Constants.SQRT_RATIO_1_2;
    uint160 constant SQRT_RATIO_2_1 = Constants.SQRT_RATIO_2_1;
    uint160 constant SQRT_RATIO_1_4 = Constants.SQRT_RATIO_1_4;
    uint160 constant SQRT_RATIO_4_1 = Constants.SQRT_RATIO_4_1;

    IPoolManager.ModifyLiquidityParams public LIQ_PARAMS =
        IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});
    IPoolManager.ModifyLiquidityParams public REMOVE_LIQ_PARAMS =
        IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -1e18});

    // Global variables
    Currency internal currency0;
    Currency internal currency1;
    PoolManager manager;
    PoolModifyLiquidityTest modifyLiquidityRouter;
    PoolSwapTest swapRouter;
    PoolDonateTest donateRouter;
    PoolTakeTest takeRouter;
    PoolInitializeTest initializeRouter;
    ProtocolFeeControllerTest feeController;
    RevertingProtocolFeeControllerTest revertingFeeController;
    OutOfBoundsProtocolFeeControllerTest outOfBoundsFeeController;
    OverflowProtocolFeeControllerTest overflowFeeController;
    InvalidReturnSizeProtocolFeeControllerTest invalidReturnSizeFeeController;

    PoolKey key;
    PoolKey nativeKey;
    PoolKey uninitializedKey;
    PoolKey uninitializedNativeKey;

    function deployFreshManager() internal {
        manager = new PoolManager(500000);
    }

    function deployFreshManagerAndRouters() internal {
        deployFreshManager();
        swapRouter = new PoolSwapTest(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        donateRouter = new PoolDonateTest(manager);
        takeRouter = new PoolTakeTest(manager);
        initializeRouter = new PoolInitializeTest(manager);
        feeController = new ProtocolFeeControllerTest();
        revertingFeeController = new RevertingProtocolFeeControllerTest();
        outOfBoundsFeeController = new OutOfBoundsProtocolFeeControllerTest();
        overflowFeeController = new OverflowProtocolFeeControllerTest();
        invalidReturnSizeFeeController = new InvalidReturnSizeProtocolFeeControllerTest();

        manager.setProtocolFeeController(feeController);
    }

    function deployMintAndApprove2Currencies() internal returns (Currency, Currency) {
        MockERC20[] memory tokens = deployTokens(2, 2 ** 255);

        address[5] memory toApprove = [
            address(swapRouter),
            address(modifyLiquidityRouter),
            address(donateRouter),
            address(takeRouter),
            address(initializeRouter)
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            tokens[0].approve(toApprove[i], Constants.MAX_UINT256);
            tokens[1].approve(toApprove[i], Constants.MAX_UINT256);
        }

        return SortTokens.sort(tokens[0], tokens[1]);
    }

    function deployTokens(uint8 count, uint256 totalSupply) internal returns (MockERC20[] memory tokens) {
        tokens = new MockERC20[](count);
        for (uint8 i = 0; i < count; i++) {
            tokens[i] = new MockERC20("TEST", "TEST", 18);
            tokens[i].mint(address(this), totalSupply);
        }
    }

    function initPool(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks,
        uint24 fee,
        uint160 sqrtPriceX96,
        bytes memory initData
    ) internal returns (PoolKey memory _key, PoolId id) {
        _key = PoolKey(_currency0, _currency1, fee, fee.isDynamicFee() ? int24(60) : int24(fee / 100 * 2), hooks);
        id = _key.toId();
        initializeRouter.initialize(_key, sqrtPriceX96, initData);
    }

    function initPoolAndAddLiquidity(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks,
        uint24 fee,
        uint160 sqrtPriceX96,
        bytes memory initData
    ) internal returns (PoolKey memory _key, PoolId id) {
        (_key, id) = initPool(_currency0, _currency1, hooks, fee, sqrtPriceX96, initData);
        modifyLiquidityRouter.modifyLiquidity{value: msg.value}(_key, LIQ_PARAMS, ZERO_BYTES);
    }

    function initPoolAndAddLiquidityETH(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks,
        uint24 fee,
        uint160 sqrtPriceX96,
        bytes memory initData,
        uint256 msgValue
    ) internal returns (PoolKey memory _key, PoolId id) {
        (_key, id) = initPool(_currency0, _currency1, hooks, fee, sqrtPriceX96, initData);
        modifyLiquidityRouter.modifyLiquidity{value: msgValue}(_key, LIQ_PARAMS, ZERO_BYTES);
    }

    // Deploys the manager, all test routers, and sets up 2 pools: with and without native
    function initializeManagerRoutersAndPoolsWithLiq(IHooks hooks) internal {
        deployFreshManagerAndRouters();
        // sets the global currencyies and key
        (currency0, currency1) = deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(currency0, currency1, hooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES);
        (nativeKey,) = initPoolAndAddLiquidityETH(
            CurrencyLibrary.NATIVE, currency1, hooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES, 1 ether
        );
        uninitializedKey = key;
        uninitializedNativeKey = nativeKey;
        uninitializedKey.fee = 100;
        uninitializedNativeKey.fee = 100;
    }

    // to receive refunds of spare eth from test helpers
    receive() external payable {}
}
