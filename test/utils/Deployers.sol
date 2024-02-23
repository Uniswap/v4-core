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
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {Constants} from "../utils/Constants.sol";
import {SortTokens} from "./SortTokens.sol";
import {PoolModifyLiquidityTest} from "../../src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "../../src/test/PoolSwapTest.sol";
import {PoolInitializeTest} from "../../src/test/PoolInitializeTest.sol";
import {PoolDonateTest} from "../../src/test/PoolDonateTest.sol";
import {PoolTakeTest} from "../../src/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "../../src/test/PoolClaimsTest.sol";
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
    using CurrencyLibrary for Currency;

    // Helpful test constants
    bytes constant ZERO_BYTES = new bytes(0);
    uint160 constant SQRT_RATIO_1_1 = Constants.SQRT_RATIO_1_1;
    uint160 constant SQRT_RATIO_1_2 = Constants.SQRT_RATIO_1_2;
    uint160 constant SQRT_RATIO_2_1 = Constants.SQRT_RATIO_2_1;
    uint160 constant SQRT_RATIO_1_4 = Constants.SQRT_RATIO_1_4;
    uint160 constant SQRT_RATIO_4_1 = Constants.SQRT_RATIO_4_1;

    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_RATIO + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_RATIO - 1;

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
    PoolClaimsTest claimsRouter;
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
        claimsRouter = new PoolClaimsTest(manager);
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

        address[6] memory toApprove = [
            address(swapRouter),
            address(modifyLiquidityRouter),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(initializeRouter)
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            tokens[0].approve(toApprove[i], Constants.MAX_UINT256);
            tokens[1].approve(toApprove[i], Constants.MAX_UINT256);
        }

        (currency0, currency1) = SortTokens.sort(tokens[0], tokens[1]);
        return (currency0, currency1);
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
        deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(currency0, currency1, hooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES);
        (nativeKey,) = initPoolAndAddLiquidityETH(
            CurrencyLibrary.NATIVE, currency1, hooks, 3000, SQRT_RATIO_1_1, ZERO_BYTES, 1 ether
        );
        uninitializedKey = key;
        uninitializedNativeKey = nativeKey;
        uninitializedKey.fee = 100;
        uninitializedNativeKey.fee = 100;
    }

    /// @notice Helper function for a simple ERC20 swaps that allows for unlimited price impact
    function swap(PoolKey memory _key, bool zeroForOne, int256 amountSpecified, bytes memory hookData)
        internal
        returns (BalanceDelta)
    {
        // allow native input for exact-input, guide users to the `swapNativeInput` function
        bool isNativeInput = zeroForOne && _key.currency0.isNative();
        if (isNativeInput) require(0 < amountSpecified, "Use swapNativeInput() for native-token exact-output swaps");

        uint256 value = isNativeInput ? uint256(amountSpecified) : 0;

        return swapRouter.swap{value: value}(
            _key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
            hookData
        );
    }

    /// @notice Helper function for a simple Native-token swap that allows for unlimited price impact
    function swapNativeInput(
        PoolKey memory _key,
        bool zeroForOne,
        int256 amountSpecified,
        bytes memory hookData,
        uint256 msgValue
    ) internal returns (BalanceDelta) {
        require(_key.currency0.isNative(), "currency0 is not native. Use swap() instead");
        if (zeroForOne == false) require(msgValue == 0, "msgValue must be 0 for oneForZero swaps");

        return swapRouter.swap{value: msgValue}(
            _key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false}),
            hookData
        );
    }

    // to receive refunds of spare eth from test helpers
    receive() external payable {}
}
