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

contract ModifyLiquidityTest is Test, Deployers, GasSnapshot {
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
        (simpleKey, simplePoolId) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_RATIO_1_1, ZERO_BYTES);
    }

    function test_modifyLiquidity_samePosition_zeroSalt_isUpdated() public {
        Position.Info memory position = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );
        assertEq(position.liquidity, 0);
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_NO_SALT, ZERO_BYTES, false, false);
        position = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        assertGt(position.liquidity, 0);

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_NO_SALT, ZERO_BYTES, false, false);
        Position.Info memory updated = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );
        assertGt(updated.liquidity, position.liquidity);
    }

    function test_modifyLiquidity_samePosition_withSalt_isUpdated() public {
        Position.Info memory position = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        assertEq(position.liquidity, 0);
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES, false, false);
        position = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        assertGt(position.liquidity, 0);

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES, false, false);
        Position.Info memory updated = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        assertGt(updated.liquidity, position.liquidity);
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
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES, false, false);

        positionNoSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        positionSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        assertEq(positionNoSalt.liquidity, 0); // This position does not have liquidity.
        assertGt(positionSalt.liquidity, 0); // This position does.

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_NO_SALT, ZERO_BYTES, false, false); // Now the positions should have the same liquidity.

        positionNoSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        positionSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );

        assertEq(positionNoSalt.liquidity, positionSalt.liquidity);

        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES, false, false);
        Position.Info memory updatedWithSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_SALT.tickLower, LIQ_PARAM_SALT.tickUpper, SALT
        );
        Position.Info memory updatedNoSalt = manager.getPosition(
            simplePoolId, address(modifyLiquidityRouter), LIQ_PARAM_NO_SALT.tickLower, LIQ_PARAM_NO_SALT.tickUpper, 0
        );

        assertGt(updatedWithSalt.liquidity, positionSalt.liquidity);
        assertGt(updatedWithSalt.liquidity, updatedNoSalt.liquidity);
        assertEq(updatedNoSalt.liquidity, positionNoSalt.liquidity);
    }

    function test_gas_modifyLiquidity_newPosition() public {
        snapStart("create new liquidity to a position with salt");
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES, false, false);
        snapEnd();

        IPoolManager.ModifyLiquidityParams memory samePositionNewSalt = LIQ_PARAM_SALT;
        samePositionNewSalt.salt = hex"BEEF";
        snapStart("create new liquidity to same position, different salt");
        modifyLiquidityRouter.modifyLiquidity(simpleKey, samePositionNewSalt, ZERO_BYTES, false, false);
        snapEnd();
    }

    function test_gas_modifyLiquidity_updateSamePosition_withSalt() public {
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES, false, false);
        snapStart("add liquidity to already existing position with salt");
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQ_PARAM_SALT, ZERO_BYTES, false, false);
        snapEnd();
    }
}
