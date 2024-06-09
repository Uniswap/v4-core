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
import {Logger} from "./utils/Logger.sol";

contract ModifyLiquidityTest is Test, Logger, Deployers, JavascriptFfi, Fuzzers, GasSnapshot {
    using StateLibrary for IPoolManager;

    PoolKey simpleKey; // vanilla pool key
    PoolId simplePoolId; // id for vanilla pool key

    bytes32 SALT = hex"CAFF";

    int128 constant ONE_PIP = 1e6;

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

    /// forge-config: default.fuzz.runs = 10
    /// forge-config: pr.fuzz.runs = 10
    /// forge-config: ci.fuzz.runs = 500
    function test_ffi_fuzz_addLiquidity_defaultPool_ReturnsCorrectLiquidityDelta(
        IPoolManager.ModifyLiquidityParams memory paramSeed
    ) public {
        // Sanitize the fuzzed params to get valid tickLower, tickUpper, and liquidityDelta.
        // We use SQRT_PRICE_1_1 because the simpleKey pool has initial sqrtPrice of SQRT_PRICE_1_1.
        IPoolManager.ModifyLiquidityParams memory params =
            createFuzzyLiquidityParams(simpleKey, paramSeed, SQRT_PRICE_1_1);

        logParams(params);

        (BalanceDelta delta) = modifyLiquidityRouter.modifyLiquidity(simpleKey, params, ZERO_BYTES);

        (int128 jsDelta0, int128 jsDelta1) = _modifyLiquidityJS(simplePoolId, params);

        _checkError(delta.amount0(), jsDelta0, "amount0 is off by more than one pip");
        _checkError(delta.amount1(), jsDelta1, "amount1 is off by more than one pip");
    }

    // Static edge case, no fuzz test, to make sure we test max tickspacing.
    function test_ffi_addLiqudity_weirdPool_0_returnsCorrectLiquidityDelta() public {
        // Use a pool with TickSpacing of MAX_TICK_SPACING
        (PoolKey memory wp0, PoolId wpId0) = initPool(
            currency0, currency1, IHooks(address(0)), 500, TickMath.MAX_TICK_SPACING, SQRT_PRICE_1_1, ZERO_BYTES
        );

        // Set the params to add random amount of liquidity to random tick boundary.
        int24 tickUpper = TickMath.MAX_TICK_SPACING * 4;
        int24 tickLower = TickMath.MAX_TICK_SPACING * -9;
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 16787899214600939458,
            salt: 0
        });

        (BalanceDelta delta) = modifyLiquidityRouter.modifyLiquidity(wp0, params, ZERO_BYTES);

        (int128 jsDelta0, int128 jsDelta1) = _modifyLiquidityJS(wpId0, params);

        _checkError(delta.amount0(), jsDelta0, "amount0 is off by more than one pip");
        _checkError(delta.amount1(), jsDelta1, "amount1 is off by more than one pip");
    }

    // Static edge case, no fuzz test, to make sure we test min tick spacing.
    function test_ffi_addLiqudity_weirdPool_1_returnsCorrectLiquidityDelta() public {
        // Use a pool with TickSpacing of MIN_TICK_SPACING
        (PoolKey memory wp0, PoolId wpId0) = initPool(
            currency0, currency1, IHooks(address(0)), 551, TickMath.MIN_TICK_SPACING, SQRT_PRICE_1_1, ZERO_BYTES
        );

        // Set the params to add random amount of liquidity to random tick boundary.
        int24 tickUpper = TickMath.MIN_TICK_SPACING * 17;
        int24 tickLower = TickMath.MIN_TICK_SPACING * 9;
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 922871614499955267459963,
            salt: 0
        });

        params.tickLower = 10;

        (BalanceDelta delta) = modifyLiquidityRouter.modifyLiquidity(wp0, params, ZERO_BYTES);

        (int128 jsDelta0, int128 jsDelta1) = _modifyLiquidityJS(wpId0, params);

        _checkError(delta.amount0(), jsDelta0, "amount0 is off by more than one pip");
        _checkError(delta.amount1(), jsDelta1, "amount1 is off by more than one pip");
    }

    function _modifyLiquidityJS(PoolId poolId, IPoolManager.ModifyLiquidityParams memory params)
        public
        returns (int128, int128)
    {
        (uint256 price, int24 tick,,) = manager.getSlot0(poolId);

        string memory jsParameters = string(
            abi.encodePacked(
                vm.toString(params.tickLower),
                ",",
                vm.toString(params.tickUpper),
                ",",
                vm.toString(params.liquidityDelta),
                ",",
                vm.toString(tick),
                ",",
                vm.toString(price)
            )
        );

        string memory scriptName = "forge-test-getModifyLiquidityResult";
        bytes memory jsResult = runScript(scriptName, jsParameters);

        int128[] memory result = abi.decode(jsResult, (int128[]));
        int128 jsDelta0 = result[0];
        int128 jsDelta1 = result[1];
        return (jsDelta0, jsDelta1);
    }

    // assert solc/js result is at most off by 1/100th of a bip (aka one pip)
    function _checkError(int128 solc, int128 js, string memory errMsg) public pure returns (int128) {
        if (solc != js) {
            // Ensures no div by 0 in the case of one-sided liquidity adds.
            (int128 gtResult, int128 ltResult) = js > solc ? (js, solc) : (solc, js);
            int128 resultsDiff = gtResult - ltResult;
            assertEq(resultsDiff * ONE_PIP / js, 0, errMsg);
        }
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
