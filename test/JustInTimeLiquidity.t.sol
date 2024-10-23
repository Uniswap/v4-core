// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Deployers} from "./utils/Deployers.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Currency} from "../src/types/Currency.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {IUnlockCallback} from "../src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {ActionsRouter, Actions} from "../src/test/ActionsRouter.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";
import {CurrencyReserves} from "../src/libraries/CurrencyReserves.sol";
import {StateLibrary} from "../src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "../src/libraries/TransientStateLibrary.sol";
import {NativeERC20} from "../src/test/NativeERC20.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {CurrencyLibrary} from "../src/types/Currency.sol";

import {Position} from "../src/libraries/Position.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {PoolId} from "../src/types/PoolId.sol";

import "forge-std/console.sol";

contract JITLiquidity is Test, Deployers, GasSnapshot {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    // PoolManager has no balance of currency2.
    Currency currency2;
    address swapper;

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
        currency2 = deployMintAndApproveCurrency();

        // seed the swapper with a balance
        swapper = makeAddr("swapper");
        currency0.transfer(swapper, 20e30);
        currency1.transfer(swapper, 20e30);
        vm.startPrank(swapper);
        MockERC20(Currency.unwrap(currency0)).approve(address(actionsRouter), type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(actionsRouter), type(uint256).max);
        vm.stopPrank();
    }

    function test_SwapWithJitLiquidity() public {
        (PoolKey memory _key, PoolId _id) =
            initPoolAndAddLiquidity(currency0, currency1, IHooks(address(0)), 200, TickMath.getSqrtPriceAtTick(0));

        IPoolManager.ModifyLiquidityParams memory params =
            IPoolManager.ModifyLiquidityParams({tickLower: -1, tickUpper: 1, liquidityDelta: 1e25, salt: 0});

        Actions[] memory actions = new Actions[](11);
        bytes[] memory actions_params = new bytes[](11);

        // -------------SETUP POOL WITH LIQUIDITY
        actions[0] = Actions.MODIFY_LIQUIDITY;
        actions_params[0] = abi.encode(_key, params, "");

        actions[1] = Actions.SYNC;
        actions_params[1] = abi.encode(currency0);

        actions[2] = Actions.TRANSFER_FROM;
        actions_params[2] = abi.encode(currency0, address(this), address(manager), type(uint256).max);

        actions[3] = Actions.SETTLE;
        actions_params[3] = abi.encode(currency0);

        actions[4] = Actions.SYNC;
        actions_params[4] = abi.encode(currency1);

        actions[5] = Actions.TRANSFER_FROM;
        actions_params[5] = abi.encode(currency1, address(this), address(manager), type(uint256).max);

        actions[6] = Actions.SETTLE;
        actions_params[6] = abi.encode(currency1);

        actionsRouter.executeActions(actions, actions_params);

        bytes32 positionId = Position.calculatePositionKey(address(actionsRouter), -120, 120, 0);

        // -------  CREATE JIT TRANSACTION
        params.salt = bytes32(bytes1(0x01));

        // ADD LIQUIDITY
        actions[0] = Actions.MODIFY_LIQUIDITY;
        params.liquidityDelta = 1e25;
        actions_params[0] = abi.encode(_key, params, "");

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 1e22,
            sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(1)
        });

        // SWAP
        actions[1] = Actions.SWAP;
        actions_params[1] = abi.encode(_key, swapParams, "");

        // REMOVE JIT
        params.liquidityDelta = -1e25;
        actions[2] = Actions.MODIFY_LIQUIDITY;
        actions_params[2] = abi.encode(_key, params, "");

        // TAKE CURRENCY 0 OUT OF POOL MANAGER
        actions[3] = Actions.TAKE;
        actions_params[3] = abi.encode(currency0, swapper, type(int128).max);

        // PAY OFF CURRENCY 1 TO POOL MANAGER
        actions[4] = Actions.SYNC;
        actions_params[4] = abi.encode(currency1);

        actions[5] = Actions.TRANSFER_FROM;
        actions_params[5] = abi.encode(currency1, swapper, address(manager), type(uint256).max);

        actions[6] = Actions.SETTLE;
        actions_params[6] = abi.encode(currency1);

        uint256 balanceBefore0 = currency0.balanceOf(swapper);
        uint256 balanceBefore1 = currency1.balanceOf(swapper);

        vm.prank(swapper);
        actionsRouter.executeActions(actions, actions_params);

        uint256 balanceAfter0 = currency0.balanceOf(swapper);
        uint256 balanceAfter1 = currency1.balanceOf(swapper);

        console.log("amount of currency 0 received: %e", balanceAfter0 - balanceBefore0);
        console.log("amount of currency 1 paid: %e", (balanceBefore1 - balanceAfter1));
    }

    function test_SwapWithoutJitLiquidity() public {
        (PoolKey memory _key, PoolId _id) =
            initPoolAndAddLiquidity(currency0, currency1, IHooks(address(0)), 200, TickMath.getSqrtPriceAtTick(0));

        IPoolManager.ModifyLiquidityParams memory params =
            IPoolManager.ModifyLiquidityParams({tickLower: -1, tickUpper: 1, liquidityDelta: 1e25, salt: 0});

        Actions[] memory actions = new Actions[](11);
        bytes[] memory actions_params = new bytes[](11);

        // SETUP POOL WITH LIQUIDITY
        actions[0] = Actions.MODIFY_LIQUIDITY;
        actions_params[0] = abi.encode(_key, params, "");

        actions[1] = Actions.SYNC;
        actions_params[1] = abi.encode(currency0);

        actions[2] = Actions.TRANSFER_FROM;
        actions_params[2] = abi.encode(currency0, address(this), address(manager), type(uint256).max);

        actions[3] = Actions.SETTLE;
        actions_params[3] = abi.encode(currency0);

        actions[4] = Actions.SYNC;
        actions_params[4] = abi.encode(currency1);

        actions[5] = Actions.TRANSFER_FROM;
        actions_params[5] = abi.encode(currency1, address(this), address(manager), type(uint256).max);

        actions[6] = Actions.SETTLE;
        actions_params[6] = abi.encode(currency1);

        actionsRouter.executeActions(actions, actions_params);

        bytes32 positionId = Position.calculatePositionKey(address(actionsRouter), -120, 120, 0);

        // -------  CREATE TRANSACTION WITHOUT JIT
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 1e22,
            sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(1)
        });

        actions[0] = Actions.SWAP;
        actions_params[0] = abi.encode(_key, swapParams, "");

        // TAKE CURRENCY 0 OUT OF POOL MANAGER
        actions[1] = Actions.TAKE;
        actions_params[1] = abi.encode(currency0, swapper, type(int128).max);

        // PAY OFF CURRENCY 1 TO POOL MANAGER
        actions[2] = Actions.SYNC;
        actions_params[2] = abi.encode(currency1);

        actions[3] = Actions.TRANSFER_FROM;
        actions_params[3] = abi.encode(currency1, swapper, address(manager), type(uint256).max);

        actions[4] = Actions.SETTLE;
        actions_params[4] = abi.encode(currency1);

        uint256 balanceBefore0 = currency0.balanceOf(swapper);
        uint256 balanceBefore1 = currency1.balanceOf(swapper);

        vm.prank(swapper);
        actionsRouter.executeActions(actions, actions_params);

        uint256 balanceAfter0 = currency0.balanceOf(swapper);
        uint256 balanceAfter1 = currency1.balanceOf(swapper);

        console.log("amount of currency 0 received: %e", balanceAfter0 - balanceBefore0);
        console.log("amount of currency 1 paid: %e", (balanceBefore1 - balanceAfter1));
    }
}
