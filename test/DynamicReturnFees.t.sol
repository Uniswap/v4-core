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
import {DynamicReturnFeeTestHook} from "../src/test/DynamicReturnFeeTestHook.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract TestDynamicReturnFees is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;

    DynamicReturnFeeTestHook dynamicFeesHooks = DynamicReturnFeeTestHook(
        address(
            uint160(
                uint256(type(uint160).max) & clearAllHookPermisssionsMask | Hooks.BEFORE_SWAP_FLAG
                    | Hooks.AFTER_INITIALIZE_FLAG
            )
        )
    );

    event Swap(
        PoolId indexed poolId,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    function setUp() public {
        DynamicReturnFeeTestHook impl = new DynamicReturnFeeTestHook();
        vm.etch(address(dynamicFeesHooks), address(impl).code);

        deployFreshManagerAndRouters();
        dynamicFeesHooks.setManager(IPoolManager(manager));

        (currency0, currency1) = deployMintAndApprove2Currencies();
        (key,) = initPoolAndAddLiquidity(
            currency0,
            currency1,
            IHooks(address(dynamicFeesHooks)),
            SwapFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_RATIO_1_1,
            ZERO_BYTES
        );
    }

    function test_returnDynamicSwapFee_beforeSwap_succeeds_gas() public {
        assertEq(_fetchPoolSwapFee(key), 0);

        dynamicFeesHooks.setFee(123);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_RATIO_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({withdrawTokens: true, settleUsingTransfer: true, currencyAlreadySent: false});

        vm.expectEmit(true, true, true, true, address(manager));
        emit Swap(key.toId(), address(swapRouter), -100, 98, 79228162514264329749955861424, 1e18, -1, 123);

        snapStart("return dynamic fee in before swap");
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        snapEnd();

        assertEq(_fetchPoolSwapFee(key), 0);
    }

    function _fetchPoolSwapFee(PoolKey memory _key) internal view returns (uint256 swapFee) {
        PoolId id = _key.toId();
        (,,, swapFee) = manager.getSlot0(id);
    }
}
