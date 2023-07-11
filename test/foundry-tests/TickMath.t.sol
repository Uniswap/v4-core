pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TickMathTest} from "../../contracts/test/TickMathTest.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";

contract TickMathTestTest is Test {
    int24 constant MIN_TICK = -887272;
    int24 constant MAX_TICK = -MIN_TICK;

    uint256 constant ONE_PIP = 1e6;

    TickMathTest tickMath;

    function setUp() public {
        tickMath = new TickMathTest();
    }

    function test_getSqrtRatioAtTick_throwsForTooLow() public {
        vm.expectRevert(TickMath.InvalidTick.selector);
        tickMath.getSqrtRatioAtTick(MIN_TICK - 1);
    }

    function test_getSqrtRatioAtTick_throwsForTooHigh() public {
        vm.expectRevert(TickMath.InvalidTick.selector);
        tickMath.getSqrtRatioAtTick(MAX_TICK + 1);
    }

    function test_getSqrtRatioAtTick_isValidMinTick() public {
        assertEq(tickMath.getSqrtRatioAtTick(MIN_TICK), 4295128739);
    }

    function test_getSqrtRatioAtTick_isValidMinTickAddOne() public {
        assertEq(tickMath.getSqrtRatioAtTick(MIN_TICK + 1), 4295343490);
    }

    function test_getSqrtRatioAtTick_isValidMaxTick() public {
        assertEq(tickMath.getSqrtRatioAtTick(MAX_TICK), 1461446703485210103287273052203988822378723970342);
    }

    function test_getSqrtRatioAtTick_isValidMaxTickSubOne() public {
        assertEq(tickMath.getSqrtRatioAtTick(MAX_TICK - 1), 1461373636630004318706518188784493106690254656249);
    }

    function testGetSqrtRatioAtTickMatchesJavaScriptImplByOneHundrethOfABip() public {
        string memory ciEnvVar;
        try vm.envString("FOUNDRY_PROFILE") returns (string memory result) {
          ciEnvVar = result;
        } catch {
          ciEnvVar = "";
        }

        // only run on ci since fuzzing with javascript is SLOW
        if (keccak256(abi.encode(ciEnvVar)) == keccak256(abi.encode("ci"))) {
            string[] memory runJsInputs = new string[](7);

            // build ffi command string
            runJsInputs[0] = "yarn";
            runJsInputs[1] = "--cwd";
            runJsInputs[2] = "js-scripts/";
            runJsInputs[3] = "--silent";
            runJsInputs[4] = "run";
            runJsInputs[5] = "forge-test-getSqrtRatioAtTick";

            int24 tick = 50;

            while(true) {
              if (tick > MAX_TICK) break;

              // test negative and positive tick
              for(uint256 i = 0; i < 2; i++) {
                tick = tick * -1;
                runJsInputs[6] = vm.toString(int256(tick));

                bytes memory jsResult = vm.ffi(runJsInputs);
                uint160 jsSqrtRatio = uint160(abi.decode(jsResult, (uint256)));
                uint160 solResult = tickMath.getSqrtRatioAtTick(tick);

                (uint160 gtResult, uint160 ltResult) =
                    jsSqrtRatio > solResult ? (jsSqrtRatio, solResult) : (solResult, jsSqrtRatio);
                uint160 resultsDiff = gtResult - ltResult;

                // assert solc/js result is at most off by 1/100th of a bip (aka one pip)
                assertEq(resultsDiff * ONE_PIP / jsSqrtRatio, 0);
              }

              tick = tick * 2;
            }
        }
    }
}
