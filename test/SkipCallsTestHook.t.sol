// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {FeeLibrary} from "../src/libraries/FeeLibrary.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IFees} from "../src/interfaces/IFees.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {IDynamicFeeManager} from "././../src/interfaces/IDynamicFeeManager.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {DynamicFeesTestHook} from "../src/test/DynamicFeesTestHook.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Constants} from "../test/utils/Constants.sol";
import {SkipCallsTestHook} from "../src/test/SkipCallsTestHook.sol";

contract SkipCallsTest is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    SkipCallsTestHook skipCallsTestHook = SkipCallsTestHook(address(uint160(Hooks.BEFORE_SWAP_FLAG)));

    function setUp() public {
        SkipCallsTestHook impl = new SkipCallsTestHook();
        vm.etch(address(skipCallsTestHook), address(impl).code);
        deployFreshManagerAndRouters();
        skipCallsTestHook.setManager(IPoolManager(manager));

        (currency0, currency1) = deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(skipCallsTestHook)), 3000, SQRT_RATIO_1_1, ZERO_BYTES
        );
    }

    function test_beforeSwap_skipIfCalledByHook() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        MockERC20(Currency.unwrap(key.currency0)).approve(address(skipCallsTestHook), Constants.MAX_UINT256);

        assertEq(skipCallsTestHook.counter(), 0);
        swapRouter.swap(key, swapParams, testSettings, abi.encode(address(this)));
        assertEq(skipCallsTestHook.counter(), 1);
    }
}
