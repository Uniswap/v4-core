// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "./utils/Deployers.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {Position} from "src/libraries/Position.sol";
import {PoolId} from "src/types/PoolId.sol";
import {PoolModifyLiquidityTest} from "../src/test/PoolModifyLiquidityTest.sol";
import {Constants} from "./utils/Constants.sol";
import {Currency} from "src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {JavascriptFfi} from "./utils/JavascriptFfi.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {Fuzzers} from "../src/test/Fuzzers.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {toBalanceDelta} from "src/types/BalanceDelta.sol";

import "forge-std/console2.sol";

contract ModifyLiquidityTest is Test, Deployers, JavascriptFfi, Fuzzers, GasSnapshot {
    using StateLibrary for IPoolManager;

    PoolKey simpleKey; // vanilla pool key
    PoolId simplePoolId; // id for vanilla pool key

    bytes32 SALT = hex"CAFF";

    IPoolManager.ModifyLiquidityParams public LIQ_PARAM_NO_SALT =
        IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: 0});

    IPoolManager.ModifyLiquidityParams public LIQ_PARAM_SALT =
        IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: SALT});

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        (simpleKey, simplePoolId) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1, ZERO_BYTES);
    }

    /*//////////////////////////////////////////////////////////////
                            Fuzz Add Liquidity
    //////////////////////////////////////////////////////////////*/

    // TODO Add fuzz
    // TODO Add array of values
    // TODO Do multiple addLiquidity/removeLiquidity calls
    // tickLower: any, tickUpper: any, liquidity: any, slot0Tick: any, slot0Price: any
    // IPoolManager.ModifyLiquidityParams memory paramSeed
    function test_fuzz_ffi_addLiquidity_defaultPool_ReturnsCorrectLiquidityDelta() public {
        IPoolManager.ModifyLiquidityParams memory boundedParams; // = createFuzzyLiquidityParams(simpleKey, paramSeed);
        boundedParams.tickLower = -120;
        boundedParams.tickUpper = 120;
        boundedParams.liquidityDelta = 1e18;

        // TODO: Support fees accrued checks.
        (BalanceDelta delta) = modifyLiquidityRouter.modifyLiquidity(simpleKey, boundedParams, ZERO_BYTES);
        console2.log(delta.amount0());
        console2.log(delta.amount1());
        console2.log(BalanceDelta.unwrap(delta));

        console2.log("top delta");
        console2.log(BalanceDelta.unwrap(toBalanceDelta(delta.amount0(), 0)));

        console2.log("hereeeee");

        uint256 priceee = TickMath.getSqrtPriceAtTick(-120);
        console2.log(priceee);

        (uint256 price, int24 tick,,) = manager.getSlot0(simplePoolId);

        string memory jsParameters = string(
            abi.encodePacked(
                vm.toString(boundedParams.tickLower),
                ",",
                vm.toString(boundedParams.tickUpper),
                ",",
                vm.toString(boundedParams.liquidityDelta),
                ",",
                vm.toString(tick),
                ",",
                vm.toString(price)
            )
        );

        console2.log(jsParameters);

        string memory scriptName = "forge-test-getModifyLiquidityResult";
        bytes memory jsResult = runScript("forge-test-getModifyLiquidityResult", jsParameters);
        console2.log("successful ffi");
        console2.logBytes(jsResult);
        int128[] memory result = abi.decode(jsResult, (int128[]));
        console2.log(result[0]);
        console2.log(result[1]);
        console2.log("successful decode");
    }

    /*//////////////////////////////////////////////////////////////
                            Salt
    //////////////////////////////////////////////////////////////*/

    function test_modifyLiquidity_samePosition_zeroSalt_isUpdated() public {
        Position.Info memory position = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );
        assertEq(position.liquidity, 0);
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_NO_SALT, ZERO_BYTES);
        position = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        assertEq(position.liquidity, uint128(uint256(LIQ_PARAM_NO_SALT.liquidityDelta)));

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_NO_SALT, ZERO_BYTES);
        Position.Info memory updated = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );
        assertEq(updated.liquidity, position.liquidity + uint128(uint256(LIQ_PARAM_NO_SALT.liquidityDelta)));
    }

    function test_modifyLiquidity_samePosition_withSalt_isUpdated() public {
        Position.Info memory position = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        assertEq(position.liquidity, 0);
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        position = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        assertEq(position.liquidity, uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        Position.Info memory updated = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        assertEq(updated.liquidity, position.liquidity + uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));
    }

    function test_modifyLiquidity_sameTicks_withDifferentSalt_isNotUpdated() public {
        Position.Info memory positionNoSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        Position.Info memory positionSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        assertEq(positionNoSalt.liquidity, 0);
        assertEq(positionSalt.liquidity, 0);

        // Modify the liquidity with the salt.
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);

        positionNoSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        positionSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        assertEq(positionNoSalt.liquidity, 0); // This position does not have liquidity.
        assertEq(positionSalt.liquidity, uint128(uint256(LIQ_PARAM_SALT.liquidityDelta))); // This position does.

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_NO_SALT, ZERO_BYTES); // Now the positions should have the same liquidity.

        positionNoSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        positionSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        // positionSalt should still only have the original liquidity deposited to it
        assertEq(positionSalt.liquidity, uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));
        assertEq(positionNoSalt.liquidity, positionSalt.liquidity);

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        Position.Info memory updatedWithSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        Position.Info memory updatedNoSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        assertEq(updatedWithSalt.liquidity, positionSalt.liquidity + uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));
        assertGt(updatedWithSalt.liquidity, updatedNoSalt.liquidity);
        assertEq(updatedNoSalt.liquidity, positionNoSalt.liquidity);
    }

    function test_modifyLiquidity_sameSalt_differentLiquidityRouters_doNotEditSamePosition() public {
        // Set up new router.
        PoolModifyLiquidityTest modifyLiquidityRouter2 = new PoolModifyLiquidityTest(manager);

        MockERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter2), Constants.MAX_UINT256);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter2), Constants.MAX_UINT256);

        IPoolManager.ModifyLiquidityParams memory LIQ_PARAM_SALT_2 =
            IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 2e18, salt: SALT});

        // Get the uninitialized positions and assert they have no liquidity.
        Position.Info memory positionSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        Position.Info memory positionSalt2 = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter2), LIQ_PARAM_SALT_2.tickLower, LIQ_PARAM_SALT_2.tickUpper, SALT
        );

        assertEq(positionSalt.liquidity, 0);
        assertEq(positionSalt2.liquidity, 0);

        // Modify the liquidity with the salt with the first router.
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);

        Position.Info memory updatedPositionSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        Position.Info memory updatedPositionSalt2 = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter2), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        // Assert only the liquidity from the first router is updated.
        assertEq(updatedPositionSalt.liquidity, uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));
        assertEq(updatedPositionSalt2.liquidity, 0);

        // Modify the liquidity with the second router.
        modifyLiquidityRouter2.modifyLiquidity(simpleKey, LIQ_PARAM_SALT_2, ZERO_BYTES);

        updatedPositionSalt2 = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter2), LIQ_PARAM_SALT_2.tickLower, LIQ_PARAM_SALT_2.tickUpper, SALT
        );
        updatedPositionSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        // Assert only the liquidity from the second router is updated.
        assertEq(updatedPositionSalt2.liquidity, uint128(uint256(LIQ_PARAM_SALT_2.liquidityDelta)));
        assertEq(updatedPositionSalt.liquidity, uint128(uint256(LIQ_PARAM_SALT.liquidityDelta)));
    }

    function test_gas_modifyLiquidity_newPosition() public {
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        snapLastCall("create new liquidity to a position with salt");
    }

    function test_gas_modifyLiquidity_updateSamePosition_withSalt() public {
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES);
        snapLastCall("add liquidity to already existing position with salt");
    }
}
