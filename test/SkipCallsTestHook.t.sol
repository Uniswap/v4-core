// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {SwapFeeLibrary} from "../src/libraries/SwapFeeLibrary.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {Deployers} from "./utils/Deployers.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Constants} from "../test/utils/Constants.sol";
import {SkipCallsTestHook} from "../src/test/SkipCallsTestHook.sol";

contract SkipCallsTest is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    IPoolManager.SwapParams swapParams =
        IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});

    PoolSwapTest.TestSettings testSettings =
        PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

    function deploy(SkipCallsTestHook skipCallsTestHook) public {
        SkipCallsTestHook impl = new SkipCallsTestHook();
        vm.etch(address(skipCallsTestHook), address(impl).code);
        deployFreshManagerAndRouters();
        skipCallsTestHook.setManager(IPoolManager(manager));

        (currency0, currency1) = deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(
            currency0, currency1, IHooks(address(skipCallsTestHook)), 3000, SQRT_RATIO_1_1, ZERO_BYTES
        );
    }

    function test_beforeInitialize_skipIfCalledByHook() public {
        SkipCallsTestHook skipCallsTestHook = SkipCallsTestHook(
            address(
                uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                    & uint160(
                        ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_ADD_LIQUIDITY_FLAG & ~Hooks.AFTER_ADD_LIQUIDITY_FLAG
                            & ~Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG & ~Hooks.AFTER_REMOVE_LIQUIDITY_FLAG & ~Hooks.BEFORE_SWAP_FLAG
                            & ~Hooks.AFTER_SWAP_FLAG & ~Hooks.BEFORE_DONATE_FLAG & ~Hooks.AFTER_DONATE_FLAG
                    )
            )
        );

        deploy(skipCallsTestHook);

        assertEq(skipCallsTestHook.counter(), 1);
    }

    function test_afterInitialize_skipIfCalledByHook() public {
        SkipCallsTestHook skipCallsTestHook = SkipCallsTestHook(
            address(
                uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                    & uint160(
                        ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.BEFORE_ADD_LIQUIDITY_FLAG & ~Hooks.AFTER_ADD_LIQUIDITY_FLAG
                            & ~Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG & ~Hooks.AFTER_REMOVE_LIQUIDITY_FLAG & ~Hooks.BEFORE_SWAP_FLAG
                            & ~Hooks.AFTER_SWAP_FLAG & ~Hooks.BEFORE_DONATE_FLAG & ~Hooks.AFTER_DONATE_FLAG
                    )
            )
        );

        deploy(skipCallsTestHook);

        assertEq(skipCallsTestHook.counter(), 1);
    }

    function test_beforeAddLiquidity_skipIfCalledByHook() public {
        SkipCallsTestHook skipCallsTestHook = SkipCallsTestHook(
            address(
                uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                    & uint160(
                        ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.AFTER_ADD_LIQUIDITY_FLAG
                            & ~Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG & ~Hooks.AFTER_REMOVE_LIQUIDITY_FLAG & ~Hooks.BEFORE_SWAP_FLAG
                            & ~Hooks.AFTER_SWAP_FLAG & ~Hooks.BEFORE_DONATE_FLAG & ~Hooks.AFTER_DONATE_FLAG
                    )
            )
        );

        deploy(skipCallsTestHook);

        assertEq(skipCallsTestHook.counter(), 1);
    }

    function test_afterAddLiquidity_skipIfCalledByHook() public {
        SkipCallsTestHook skipCallsTestHook = SkipCallsTestHook(
            address(
                uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                    & uint160(
                        ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                            & ~Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG & ~Hooks.AFTER_REMOVE_LIQUIDITY_FLAG & ~Hooks.BEFORE_SWAP_FLAG
                            & ~Hooks.AFTER_SWAP_FLAG & ~Hooks.BEFORE_DONATE_FLAG & ~Hooks.AFTER_DONATE_FLAG
                    )
            )
        );

        deploy(skipCallsTestHook);

        assertEq(skipCallsTestHook.counter(), 1);
    }

    function test_beforeRemoveLiquidity_skipIfCalledByHook() public {
        SkipCallsTestHook skipCallsTestHook = SkipCallsTestHook(
            address(
                uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                    & uint160(
                        ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                            & ~Hooks.AFTER_ADD_LIQUIDITY_FLAG & ~Hooks.AFTER_REMOVE_LIQUIDITY_FLAG & ~Hooks.BEFORE_SWAP_FLAG
                            & ~Hooks.AFTER_SWAP_FLAG & ~Hooks.BEFORE_DONATE_FLAG & ~Hooks.AFTER_DONATE_FLAG
                    )
            )
        );

        deploy(skipCallsTestHook);

        MockERC20(Currency.unwrap(key.currency0)).approve(address(skipCallsTestHook), Constants.MAX_UINT256);
        MockERC20(Currency.unwrap(key.currency1)).approve(address(skipCallsTestHook), Constants.MAX_UINT256);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, abi.encode(address(this)));
        assertEq(skipCallsTestHook.counter(), 1);
    }

    function test_afterRemoveLiquidity_skipIfCalledByHook() public {
        SkipCallsTestHook skipCallsTestHook = SkipCallsTestHook(
            address(
                uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                    & uint160(
                        ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                            & ~Hooks.AFTER_ADD_LIQUIDITY_FLAG & ~Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG & ~Hooks.BEFORE_SWAP_FLAG
                            & ~Hooks.AFTER_SWAP_FLAG & ~Hooks.BEFORE_DONATE_FLAG & ~Hooks.AFTER_DONATE_FLAG
                    )
            )
        );

        deploy(skipCallsTestHook);

        MockERC20(Currency.unwrap(key.currency0)).approve(address(skipCallsTestHook), Constants.MAX_UINT256);
        MockERC20(Currency.unwrap(key.currency1)).approve(address(skipCallsTestHook), Constants.MAX_UINT256);
        modifyLiquidityRouter.modifyLiquidity(key, LIQ_PARAMS, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQ_PARAMS, abi.encode(address(this)));
        assertEq(skipCallsTestHook.counter(), 1);
    }

    function test_beforeSwap_skipIfCalledByHook() public {
        SkipCallsTestHook skipCallsTestHook = SkipCallsTestHook(
            address(
                uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                    & uint160(
                        ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                            & ~Hooks.AFTER_ADD_LIQUIDITY_FLAG & ~Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                            & ~Hooks.AFTER_REMOVE_LIQUIDITY_FLAG & ~Hooks.AFTER_SWAP_FLAG & ~Hooks.BEFORE_DONATE_FLAG
                            & ~Hooks.AFTER_DONATE_FLAG
                    )
            )
        );

        deploy(skipCallsTestHook);

        MockERC20(Currency.unwrap(key.currency0)).approve(address(skipCallsTestHook), Constants.MAX_UINT256);

        assertEq(skipCallsTestHook.counter(), 0);
        swapRouter.swap(key, swapParams, testSettings, abi.encode(address(this)));
        assertEq(skipCallsTestHook.counter(), 1);
    }

    function test_afterSwap_skipIfCalledByHook() public {
        SkipCallsTestHook skipCallsTestHook = SkipCallsTestHook(
            address(
                uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                    & uint160(
                        ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                            & ~Hooks.AFTER_ADD_LIQUIDITY_FLAG & ~Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                            & ~Hooks.AFTER_REMOVE_LIQUIDITY_FLAG & ~Hooks.BEFORE_SWAP_FLAG & ~Hooks.BEFORE_DONATE_FLAG
                            & ~Hooks.AFTER_DONATE_FLAG
                    )
            )
        );

        deploy(skipCallsTestHook);

        MockERC20(Currency.unwrap(key.currency0)).approve(address(skipCallsTestHook), Constants.MAX_UINT256);

        assertEq(skipCallsTestHook.counter(), 0);
        swapRouter.swap(key, swapParams, testSettings, abi.encode(address(this)));
        assertEq(skipCallsTestHook.counter(), 1);
    }

    function test_beforeDonate_skipIfCalledByHook() public {
        SkipCallsTestHook skipCallsTestHook = SkipCallsTestHook(
            address(
                uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                    & uint160(
                        ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                            & ~Hooks.AFTER_ADD_LIQUIDITY_FLAG & ~Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                            & ~Hooks.AFTER_REMOVE_LIQUIDITY_FLAG & ~Hooks.BEFORE_SWAP_FLAG & ~Hooks.AFTER_SWAP_FLAG
                            & ~Hooks.AFTER_DONATE_FLAG
                    )
            )
        );

        deploy(skipCallsTestHook);

        assertEq(skipCallsTestHook.counter(), 0);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(skipCallsTestHook), Constants.MAX_UINT256);
        MockERC20(Currency.unwrap(key.currency1)).approve(address(skipCallsTestHook), Constants.MAX_UINT256);
        donateRouter.donate(key, 100, 200, abi.encode(address(this)));
        assertEq(skipCallsTestHook.counter(), 1);
    }

    function test_afterDonate_skipIfCalledByHook() public {
        SkipCallsTestHook skipCallsTestHook = SkipCallsTestHook(
            address(
                uint160(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
                    & uint160(
                        ~Hooks.BEFORE_INITIALIZE_FLAG & ~Hooks.AFTER_INITIALIZE_FLAG & ~Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                            & ~Hooks.AFTER_ADD_LIQUIDITY_FLAG & ~Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                            & ~Hooks.AFTER_REMOVE_LIQUIDITY_FLAG & ~Hooks.BEFORE_SWAP_FLAG & ~Hooks.AFTER_SWAP_FLAG
                            & ~Hooks.BEFORE_DONATE_FLAG
                    )
            )
        );

        deploy(skipCallsTestHook);

        assertEq(skipCallsTestHook.counter(), 0);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(skipCallsTestHook), Constants.MAX_UINT256);
        MockERC20(Currency.unwrap(key.currency1)).approve(address(skipCallsTestHook), Constants.MAX_UINT256);
        donateRouter.donate(key, 100, 200, abi.encode(address(this)));
        assertEq(skipCallsTestHook.counter(), 1);
    }
}
