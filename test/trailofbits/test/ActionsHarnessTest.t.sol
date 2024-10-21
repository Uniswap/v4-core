// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "test/trailofbits/ActionFuzzEntrypoint.sol";

import {Pool} from "src/libraries/Pool.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "src/types/Currency.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {TransientStateLibrary} from "src/libraries/TransientStateLibrary.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {FixedPoint128} from "src/libraries/FixedPoint128.sol";

/// @notice This test contract gives us a way to detect potential regressions in the Actions fuzzing harness and
/// explitily test regression sequences that were caused by false positives.
contract ActionsHarness_Test is Test {
    ActionFuzzEntrypoint target;

    using Pool for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using TransientStateLibrary for IPoolManager;
    using StateLibrary for IPoolManager;

    function setUp() public {
        target = new ActionFuzzEntrypoint();
        payable(address(target)).transfer(address(this).balance - 20 ether);
        payable(address(target.getActionRouter())).transfer(20 ether);
    }

    function test_sync_test() public {
        target.addSync(uint8(0));
    }

    function test_initialize_and_add_liquidity_settle() public {
        target.addInitializeAndAddLiquidity(0, 1, 1, 79228162514264337593543950336, 0, -887272, 887272, 1 ether, 0);
        target.addSync(uint8(0));
        target.addTransferFrom(0, 1 ether, address(target), address(target.getManager()));
        target.addSettle();
        target.addSync(uint8(1));
        target.addTransferFrom(1, 1 ether, address(target), address(target.getManager()));
        target.addSettle();
        target.runActions();
    }

    function test_initialize_and_add_liquidity_settle_for() public {
        target.addInitializeAndAddLiquidity(0, 1, 1, 79228162514264337593543950336, 0, -887272, 887272, 1 ether, 0);
        target.addSync(uint8(0));
        target.addTransferFrom(0, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.addSync(uint8(1));
        target.addTransferFrom(1, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.runActions();
    }

    function test_donate() public {
        target.addInitializeAndAddLiquidity(0, 1, 1, 79228162514264337593543950336, 0, -887272, 887272, 1 ether, 0);
        target.addSync(uint8(0));
        target.addTransferFrom(0, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.addSync(uint8(1));
        target.addTransferFrom(1, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.runActions();

        target.addDonate(0, 0.5 ether, 0.5 ether);
        target.addSync(uint8(0));
        target.addTransferFrom(0, 0.5 ether, address(target), address(target.getManager()));
        target.addSettle();
        target.addSync(uint8(1));
        target.addTransferFrom(1, 0.5 ether, address(target), address(target.getManager()));
        target.addSettle();
        target.runActions();
    }

    function test_take_settle() public {
        target.addSync(uint8(0));
        target.addTransferFrom(0, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.addSync(uint8(0));
        target.addTake(0, 1 ether);
        target.runActions();
    }

    function test_swap() public {
        target.addInitializeAndAddLiquidity(0, 1, 1, 79228162514264337593543950336, 0, -887272, 887272, 1 ether, 0);
        target.addSync(uint8(0));
        target.addTransferFrom(0, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.addSync(uint8(1));
        target.addTransferFrom(1, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.runActions();

        target.addSwap(0, -0.5 ether, true);
        target.addSync(uint8(0));
        target.addTransferFrom(0, 0.5 ether, address(target), address(target.getManager()));
        target.addSettle();

        target.addSync(uint8(1));
        target.addTake(1, 333333333333333313);
        target.runActions();
    }

    function test_swap2() public {
        target.addInitializeAndAddLiquidity(0, 1, 1, 79228162514264337593543950336, 0, -887272, 887272, 1 ether, 0);
        target.addSync(uint8(0));
        target.addTransferFrom(0, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.addSync(uint8(1));
        target.addTransferFrom(1, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.runActions();

        target.addSwap(0, -0.5 ether, false);
        target.addSync(uint8(1));
        target.addTransferFrom(1, 0.5 ether, address(target), address(target.getManager()));
        target.addSettle();

        target.addSync(uint8(0));
        target.addTake(0, 333333333333333311);
        target.runActions();
    }

    function test_mint() public {
        target.addInitializeAndAddLiquidity(0, 1, 1, 79228162514264337593543950336, 0, -887272, 887272, 1 ether, 0);
        target.addSync(uint8(0));
        target.addTransferFrom(0, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.addSync(uint8(1));
        target.addTransferFrom(1, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.runActions();

        target.addSwap(0, -0.5 ether, false);
        target.addSync(uint8(1));
        target.addTransferFrom(1, 0.5 ether, address(target), address(target.getManager()));
        target.addSettle();

        target.addSync(uint8(0));
        target.addMint(address(target), 0, 333333333333333311);
        target.runActions();
    }

    function test_settle_native() public {
        uint8 nativeCurrencyIdx = uint8(target.NUMBER_CURRENCIES() - 1);

        target.addInitializeAndAddLiquidity(
            0, nativeCurrencyIdx, 1, 79228162514264337593543950336, 0, -887272, 887272, 1 ether, 0
        );
        target.addSync(uint8(0));

        target.addTransferFrom(0, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));

        target.addSync(uint8(nativeCurrencyIdx));
        target.addSettleNative(1 ether);
        target.runActions();

        target.addSwap(0, -0.5 ether, true);
        target.addSync(nativeCurrencyIdx);
        target.addSettleNative(0.5 ether);

        target.addSync(uint8(0));
        target.addTake(0, 333333333333333313);
        target.runActions();
    }

    function test_addShortcutSettle() public {
        target.addInitializeAndAddLiquidity(0, 1, 1, 79228162514264337593543950336, 0, -887272, 887272, 1 ether, 0);
        target.addSync(uint8(0));
        target.addTransferFrom(0, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.addSync(uint8(1));
        target.addTransferFrom(1, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.runActions();

        target.addSwap(0, -0.5 ether, false);
        target.addShortcutSettle();
        target.runActions();
    }

    function test_burn() public {
        target.addInitializeAndAddLiquidity(0, 1, 1, 79228162514264337593543950336, 0, -887272, 887272, 1 ether, 0);
        target.addSync(uint8(0));
        target.addTransferFrom(0, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.addSync(uint8(1));
        target.addTransferFrom(1, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.runActions();

        target.addSync(uint8(0));
        target.addMint(address(target.getActionRouter()), 0, 1 ether);
        target.addBurn(address(target.getActionRouter()), 0, 1 ether);

        target.addSettle();
        target.runActions();
    }

    function test_clear() public {
        target.addInitializeAndAddLiquidity(0, 1, 1, 79228162514264337593543950336, 0, -887272, 887272, 1 ether, 0);
        target.addSync(uint8(0));
        target.addTransferFrom(0, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.addSync(uint8(1));
        target.addTransferFrom(1, 1 ether, address(target), address(target.getManager()));
        target.addSettleFor(address(target.getActionRouter()));
        target.runActions();

        target.addSwap(0, -0.5 ether, false);
        target.addSync(uint8(1));
        target.addTransferFrom(1, 0.5 ether, address(target), address(target.getManager()));
        target.addSettle();

        target.addSync(uint8(0));
        target.addClear(0, 333333333333333311);
        target.runActions();
    }

    function test_swapin_out() public {
        target.addInitializeAndAddLiquidity(0, 1, 1, 79228162514264337593543950336, 0, -887272, 887272, 1 ether, 0);
        target.addSwapInSwapOut(0, true, 1 ether);
        target.runActions();
    }

    function test_feegrowth_overflow() public {
        int128 amount = 1;
        target.addInitializeAndAddLiquidityAndSettle(0, 1, 1, 79228162514264337593543950336, 1_000_000, 0, 1, amount, 0);
        PoolId poolId = abi.decode(hex"ad005400d48c3dc36756210997b5869d257ca207f4d5085e1bd29919092d6a97", (PoolId));
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            IPoolManager(target.getManager()).getFeeGrowthInside(poolId, 0, 1);

        for (uint256 i = 0; i < 3; i++) {
            console2.logUint(i);
            target.addDonate(0, uint128(type(int128).max), uint128(type(int128).max));
            target.addShortcutSettle();
            target.runActions();
        }

        (feeGrowthInside0X128, feeGrowthInside1X128) =
            IPoolManager(target.getManager()).getFeeGrowthInside(poolId, 0, 1);

        console2.logUint(feeGrowthInside0X128 / FixedPoint128.Q128);
        console2.logUint(feeGrowthInside1X128 / FixedPoint128.Q128);
    }

    function test_targeted_pool() public {
        target.addTargetedPoolReadyToOverflow(0, 1, 0);
    }

    /*
    Protocol fee collection properties are disabled due to the fixes from TOB-UNI4-3
    function test_fee_miscalculation_regression() public {
        target.addTargetedPool(1,0,0,99);
        target.addModifyPositionAndRunActions(0,0,-1,934735867213017,13541478287070347540639706863682772478921284014365313132303827141936693186);
        target.addSetNewProtocolFee(0,1);
        target.addSwapAndRunActions(0,4110922,true);
    }

    function test_shadowaccounting_regression_1() public {
        target.addTargetedPool(0,3,0,273233);
        target.addModifyPositionAndRunActions(0,-2,0,248701260024546,1115970101497554417622751038604682045916585273685975242110649999204994190);
        target.addSetNewProtocolFee(0,1);
        target.addSwapAndRunActions(0,33216723,true);
    }
    */

    function test_shadowaccounting_regression_2() public {
        target.addTargetedPool(1, 0, 0, 1);
        target.addModifyPositionAndRunActions(
            0, -1001, -161, 1478484426, 115792089237316195423570985008687907853269984665640564039457584007913129637888
        );
        target.addSwapAndRunActions(0, 1, true);
        target.addDonateAndSettle(0, 2);
        target.addModifyPositionAndRunActions(
            0, -1001, -161, 277295330, 115792089237316195423570985008687907853269984665640564039457584007913129637888
        );
    }

    function test_shadowaccounting_regression_3() public {
        target.addTargetedPool(0, 59, 1, -335483349064151699904);
        target.addModifyPosition(35, 0, 17096, 53, 82970313381531717844305482713703611020253841721915);
        target.addSettleFor(address(0));
        target.addBurnAndRunActions(address(0), 16, 0);
    }

    function test_shadowaccounting_regression_4() public {
        target.addSync(0);
        vm.roll(block.number + 38894);
        target.runActions();
        vm.roll(block.number + 38894);
        target.addSettleFor(address(0));
        vm.roll(block.number + 38894);
        target.runActions();
    }

    function test_swap_through_fee_overflow_pool() public {
        target.addTargetedPoolReadyToOverflow(1, 0, 1);
        target.addModifyPosition(0, 2, 1, 1, 2367934173550170961037218246786631748697795);
        target.addSwap(0, -3, false);
        target.addDonateAndSettle(0, 0);
    }

    function test_swap_through_fee_overflow_pool2() public {
        target.addTargetedPoolReadyToOverflow(1, 0, 1);
        target.addModifyPosition(0, 0, 1, 2, 2367934173550170961037218246786631748697795);
        target.addDonateAndSettle(5, 5);
        target.addSwap(0, -3, false);
        target.addShortcutSettle();
        target.runActions();
    }

    function test_poolliquidity_regression_1() public {
        target.addTargetedPoolReadyToOverflow(247, 0, 6909592);
        target.addModifyPositionAndRunActions(
            0, -14, 2530466, 2812, 115792089237316195423570985008687907853269984665640564039457584007913129638913
        );
        target.addSwapAndRunActions(0, 92274097787679228392889020467702269147, false);
        target.addModifyPositionAndRunActions(
            0, -14, 2530466, 793, 115792089237316195423570985008687907853269984665640564039457584007913129638913
        );
    }
}
