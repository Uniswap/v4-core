// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Oracle} from "../../contracts/libraries/Oracle.sol";
import {OracleTest} from "../../contracts/test/OracleTest.sol";
import {BitMath} from "../../contracts/libraries/BitMath.sol";

contract TestOracle is Test, GasSnapshot {
    OracleTest initializedOracle;
    OracleTest oracle;

    function setUp() public {
        oracle = new OracleTest();
        initializedOracle = new OracleTest();
        initializedOracle.initialize(OracleTest.InitializeParams({time: 0, tick: 0, liquidity: 0}));
    }

    function testInitialize() public {
        snapStart("OracleInitialize");
        oracle.initialize(OracleTest.InitializeParams({time: 1, tick: 1, liquidity: 1}));
        snapEnd();

        assertEq(oracle.index(), 0);
        assertEq(oracle.cardinality(), 1);
        assertEq(oracle.cardinalityNext(), 1);
        assertObservation(
            oracle,
            0,
            Oracle.Observation({
                blockTimestamp: 1,
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: 0,
                initialized: true
            })
        );
    }

    function testGrow() public {
        initializedOracle.grow(5);
        assertEq(initializedOracle.index(), 0);
        assertEq(initializedOracle.cardinality(), 1);
        assertEq(initializedOracle.cardinalityNext(), 5);

        // does not touch first slot
        assertObservation(
            initializedOracle,
            0,
            Oracle.Observation({
                blockTimestamp: 0,
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: 0,
                initialized: true
            })
        );

        // adds data to all slots
        for (uint64 i = 1; i < 5; i++) {
            assertObservation(
                initializedOracle,
                i,
                Oracle.Observation({
                    blockTimestamp: 1,
                    tickCumulative: 0,
                    secondsPerLiquidityCumulativeX128: 0,
                    initialized: false
                })
            );
        }

        // noop if initializedOracle is already gte size
        initializedOracle.grow(3);
        assertEq(initializedOracle.index(), 0);
        assertEq(initializedOracle.cardinality(), 1);
        assertEq(initializedOracle.cardinalityNext(), 5);
    }

    function testGrowAfterWrap() public {
        initializedOracle.grow(2);
        // index is now 1
        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 2, liquidity: 1, tick: 1}));
        // index is now 0 again
        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 2, liquidity: 1, tick: 1}));
        assertEq(initializedOracle.index(), 0);
        initializedOracle.grow(3);

        assertEq(initializedOracle.index(), 0);
        assertEq(initializedOracle.cardinality(), 2);
        assertEq(initializedOracle.cardinalityNext(), 3);
    }

    function testGas1Slot() public {
        snapStart("OracleGrow1Slot");
        initializedOracle.grow(2);
        snapEnd();
    }

    function testGas10Slots() public {
        snapStart("OracleGrow10Slots");
        initializedOracle.grow(11);
        snapEnd();
    }

    function testGas1SlotCardinalityGreater() public {
        initializedOracle.grow(2);
        snapStart("OracleGrow1SlotCardinalityGreater");
        initializedOracle.grow(3);
        snapEnd();
    }

    function testGas10SlotCardinalityGreater() public {
        initializedOracle.grow(2);
        snapStart("OracleGrow10SlotsCardinalityGreater");
        initializedOracle.grow(12);
        snapEnd();
    }

    function testWrite() public {
        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 1, tick: 2, liquidity: 5}));
        assertEq(initializedOracle.index(), 0);
        assertObservation(
            initializedOracle,
            0,
            Oracle.Observation({
                blockTimestamp: 1,
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: 340282366920938463463374607431768211456,
                initialized: true
            })
        );

        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 5, tick: -1, liquidity: 8}));
        assertEq(initializedOracle.index(), 0);
        assertObservation(
            initializedOracle,
            0,
            Oracle.Observation({
                blockTimestamp: 6,
                tickCumulative: 10,
                secondsPerLiquidityCumulativeX128: 680564733841876926926749214863536422912,
                initialized: true
            })
        );

        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 3, tick: 2, liquidity: 3}));
        assertEq(initializedOracle.index(), 0);
        assertObservation(
            initializedOracle,
            0,
            Oracle.Observation({
                blockTimestamp: 9,
                tickCumulative: 7,
                secondsPerLiquidityCumulativeX128: 808170621437228850725514692650449502208,
                initialized: true
            })
        );
    }

    function testWriteAddsNothingIfTimeUnchanged() public {
        initializedOracle.grow(2);
        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 1, tick: 3, liquidity: 2}));
        assertEq(initializedOracle.index(), 1);
        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 0, tick: -5, liquidity: 9}));
        assertEq(initializedOracle.index(), 1);
    }

    function testWriteTimeChanged() public {
        initializedOracle.grow(3);
        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 6, tick: 3, liquidity: 2}));
        assertEq(initializedOracle.index(), 1);
        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: -5, liquidity: 9}));
        assertEq(initializedOracle.index(), 2);
        assertObservation(
            initializedOracle,
            1,
            Oracle.Observation({
                blockTimestamp: 6,
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: 2041694201525630780780247644590609268736,
                initialized: true
            })
        );
    }

    function testWriteGrowsCardinalityWritingPast() public {
        initializedOracle.grow(2);
        initializedOracle.grow(4);
        assertEq(initializedOracle.cardinality(), 1);
        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 3, tick: 5, liquidity: 6}));
        assertEq(initializedOracle.cardinality(), 4);
        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: 6, liquidity: 4}));
        assertEq(initializedOracle.cardinality(), 4);
        assertEq(initializedOracle.index(), 2);
        assertObservation(
            initializedOracle,
            2,
            Oracle.Observation({
                blockTimestamp: 7,
                tickCumulative: 20,
                secondsPerLiquidityCumulativeX128: 1247702012043441032699040227249816775338,
                initialized: true
            })
        );
    }

    function testWriteWrapsAround() public {
        initializedOracle.grow(3);
        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 3, tick: 1, liquidity: 2}));

        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: 2, liquidity: 3}));

        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 5, tick: 3, liquidity: 4}));

        assertEq(initializedOracle.index(), 0);
        assertObservation(
            initializedOracle,
            0,
            Oracle.Observation({
                blockTimestamp: 12,
                tickCumulative: 14,
                secondsPerLiquidityCumulativeX128: 2268549112806256423089164049545121409706,
                initialized: true
            })
        );
    }

    function testWriteAccumulatesLiquidity() public {
        initializedOracle.grow(4);
        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 3, tick: 3, liquidity: 2}));

        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: -7, liquidity: 6}));

        initializedOracle.update(OracleTest.UpdateParams({advanceTimeBy: 5, tick: -2, liquidity: 4}));

        assertEq(initializedOracle.index(), 3);

        assertObservation(
            initializedOracle,
            1,
            Oracle.Observation({
                blockTimestamp: 3,
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: 1020847100762815390390123822295304634368,
                initialized: true
            })
        );
        assertObservation(
            initializedOracle,
            2,
            Oracle.Observation({
                blockTimestamp: 7,
                tickCumulative: 12,
                secondsPerLiquidityCumulativeX128: 1701411834604692317316873037158841057280,
                initialized: true
            })
        );
        assertObservation(
            initializedOracle,
            3,
            Oracle.Observation({
                blockTimestamp: 12,
                tickCumulative: -23,
                secondsPerLiquidityCumulativeX128: 1984980473705474370203018543351981233493,
                initialized: true
            })
        );
        assertObservation(
            initializedOracle,
            4,
            Oracle.Observation({
                blockTimestamp: 0,
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: 0,
                initialized: false
            })
        );
    }

    function testObserveFailsBeforeInitialize() public {
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        vm.expectRevert(Oracle.OracleCardinalityCannotBeZero.selector);
        oracle.observe(secondsAgos);
    }

    function testObserveFailsIfOlderDoesNotExist() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 4, tick: 2, time: 5}));
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 1;
        vm.expectRevert(abi.encodeWithSelector(Oracle.TargetPredatesOldestObservation.selector, 5, 4));
        oracle.observe(secondsAgos);
    }

    function testDoesNotFailAcrossOverflowBoundary() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 4, tick: 2, time: 2 ** 32 - 1}));
        oracle.advanceTime(2);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 1);
        assertEq(tickCumulative, 2);
        assertEq(secondsPerLiquidityCumulativeX128, 85070591730234615865843651857942052864);
    }

    function testInterpolationMaxLiquidity() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: type(uint128).max, tick: 0, time: 0}));
        oracle.grow(2);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 13, tick: 0, liquidity: 0}));
        (, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(secondsPerLiquidityCumulativeX128, 13);
        (, secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 6);
        assertEq(secondsPerLiquidityCumulativeX128, 7);
        (, secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 12);
        assertEq(secondsPerLiquidityCumulativeX128, 1);
        (, secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 13);
        assertEq(secondsPerLiquidityCumulativeX128, 0);
    }

    function testInterpolatesSame0And1Liquidity() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 1, tick: 0, time: 0}));
        oracle.grow(2);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 13, tick: 0, liquidity: type(uint128).max}));
        (, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(secondsPerLiquidityCumulativeX128, 13 << 128);
        (, secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 6);
        assertEq(secondsPerLiquidityCumulativeX128, 7 << 128);
        (, secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 12);
        assertEq(secondsPerLiquidityCumulativeX128, 1 << 128);
        (, secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 13);
        assertEq(secondsPerLiquidityCumulativeX128, 0);
    }

    function testInterpolatesAcrossChunkBoundaries() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 0, tick: 0, time: 0}));
        oracle.grow(2);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 2 ** 32 - 6, tick: 0, liquidity: 0}));
        (, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(secondsPerLiquidityCumulativeX128, (2 ** 32 - 6) << 128);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 13, tick: 0, liquidity: 0}));
        (, secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(secondsPerLiquidityCumulativeX128, 7 << 128);

        // interpolation checks
        (, secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 3);
        assertEq(secondsPerLiquidityCumulativeX128, 4 << 128);
        (, secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 8);
        assertEq(secondsPerLiquidityCumulativeX128, (2 ** 32 - 1) << 128);
    }

    function testSingleObservationAtCurrentTime() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 4, tick: 2, time: 5}));
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, 0);
        assertEq(secondsPerLiquidityCumulativeX128, 0);
    }

    function testSingleObservationInRecentPast() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 4, tick: 2, time: 5}));
        oracle.advanceTime(3);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 4;
        vm.expectRevert(abi.encodeWithSelector(Oracle.TargetPredatesOldestObservation.selector, 5, 4));
        oracle.observe(secondsAgos);
    }

    function testSingleObservationSecondsAgo() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 4, tick: 2, time: 5}));
        oracle.advanceTime(3);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 3);
        assertEq(tickCumulative, 0);
        assertEq(secondsPerLiquidityCumulativeX128, 0);
    }

    function testSingleObservationInPastCounterfactualInPast() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 4, tick: 2, time: 5}));
        oracle.advanceTime(3);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 1);
        assertEq(tickCumulative, 4);
        assertEq(secondsPerLiquidityCumulativeX128, 170141183460469231731687303715884105728);
    }

    function testSingleObservationInPastCounterfactualNow() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 4, tick: 2, time: 5}));
        oracle.advanceTime(3);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, 6);
        assertEq(secondsPerLiquidityCumulativeX128, 255211775190703847597530955573826158592);
    }

    function testTwoObservationsChronologicalZeroSecondsAgoExact() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -20);
        assertEq(secondsPerLiquidityCumulativeX128, 272225893536750770770699685945414569164);
    }

    function testTwoObservationsChronologicalZeroSecondsAgoCounterfactual() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -13);
        assertEq(secondsPerLiquidityCumulativeX128, 1463214177760035392892510811956603309260);
    }

    function testTwoObservationsChronologicalSecondsAgoExactlyFirstObservation() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 11);
        assertEq(tickCumulative, 0);
        assertEq(secondsPerLiquidityCumulativeX128, 0);
    }

    function testTwoObservationsChronologicalSecondsAgoBetween() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 9);
        assertEq(tickCumulative, -10);
        assertEq(secondsPerLiquidityCumulativeX128, 136112946768375385385349842972707284582);
    }

    function testTwoObservationsReverseOrderZeroSecondsAgoExact() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 3, tick: -5, liquidity: 4}));
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -17);
        assertEq(secondsPerLiquidityCumulativeX128, 782649443918158465965761597093066886348);
    }

    function testTwoObservationsReverseOrderZeroSecondsAgoCounterfactual() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 3, tick: -5, liquidity: 4}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -52);
        assertEq(secondsPerLiquidityCumulativeX128, 1378143586029800777026667160098661256396);
    }

    function testTwoObservationsReverseOrderSecondsAgoExactlyOnFirstObservation() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 3, tick: -5, liquidity: 4}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 10);
        assertEq(tickCumulative, -20);
        assertEq(secondsPerLiquidityCumulativeX128, 272225893536750770770699685945414569164);
    }

    function testTwoObservationsReverseOrderSecondsAgoBetween() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 3, tick: -5, liquidity: 4}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 9);
        assertEq(tickCumulative, -19);
        assertEq(secondsPerLiquidityCumulativeX128, 442367076997220002502386989661298674892);
    }

    function testCanFetchMultipleObservations() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 2 ** 15, tick: 2, time: 5}));
        oracle.grow(4);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 13, tick: 6, liquidity: 2 ** 12}));
        oracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](6);
        secondsAgos[0] = 0;
        secondsAgos[1] = 3;
        secondsAgos[2] = 8;
        secondsAgos[3] = 13;
        secondsAgos[4] = 15;
        secondsAgos[5] = 18;
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            oracle.observe(secondsAgos);
        assertEq(tickCumulatives.length, 6);
        assertEq(tickCumulatives[0], 56);
        assertEq(tickCumulatives[1], 38);
        assertEq(tickCumulatives[2], 20);
        assertEq(tickCumulatives[3], 10);
        assertEq(tickCumulatives[4], 6);
        assertEq(tickCumulatives[5], 0);
        assertEq(secondsPerLiquidityCumulativeX128s.length, 6);
        assertEq(secondsPerLiquidityCumulativeX128s[0], 550383467004691728624232610897330176);
        assertEq(secondsPerLiquidityCumulativeX128s[1], 301153217795020002454768787094765568);
        assertEq(secondsPerLiquidityCumulativeX128s[2], 103845937170696552570609926584401920);
        assertEq(secondsPerLiquidityCumulativeX128s[3], 51922968585348276285304963292200960);
        assertEq(secondsPerLiquidityCumulativeX128s[4], 31153781151208965771182977975320576);
        assertEq(secondsPerLiquidityCumulativeX128s[5], 0);
    }

    function testObserveGasSinceMostRecent() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.advanceTime(2);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 1;
        snap("OracleObserveSinceMostRecent", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testObserveGasCurrentTime() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("OracleObserveCurrentTime", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testObserveGasCurrentTimeCounterfactual() public {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        initializedOracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("OracleObserveCurrentTimeCounterfactual", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testManyObservationsSimpleReads(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        assertEq(oracle.index(), 1);
        assertEq(oracle.cardinality(), 5);
        assertEq(oracle.cardinalityNext(), 5);
    }

    function testManyObservationsLatestObservationSameTimeAsLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -21);
        assertEq(secondsPerLiquidityCumulativeX128, 2104079302127802832415199655953100107502);
    }

    function testManyObservationsLatestObservation5SecondsAfterLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        // latest observation 5 seconds after latest
        oracle.advanceTime(5);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 5);
        assertEq(tickCumulative, -21);
        assertEq(secondsPerLiquidityCumulativeX128, 2104079302127802832415199655953100107502);
    }

    function testManyObservationsCurrentObservation5SecondsAfterLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        oracle.advanceTime(5);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, 9);
        assertEq(secondsPerLiquidityCumulativeX128, 2347138135642758877746181518404363115684);
    }

    function testManyObservationsBetweenLatestObservationAtLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 3);
        assertEq(tickCumulative, -33);
        assertEq(secondsPerLiquidityCumulativeX128, 1593655751746395137220137744805447790318);
    }

    function testManyObservationsBetweenLatestObservationAfterLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        oracle.advanceTime(5);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 8);
        assertEq(tickCumulative, -33);
        assertEq(secondsPerLiquidityCumulativeX128, 1593655751746395137220137744805447790318);
    }

    function testManyObservationsOlderThanOldestReverts(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        (uint32 oldestTimestamp,,,) = oracle.observations(oracle.index() + 1);
        uint32 secondsAgo = 15;
        // overflow desired here
        uint32 target;
        unchecked {
            target = oracle.time() - secondsAgo;
        }

        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = secondsAgo;
        vm.expectRevert(
            abi.encodeWithSelector(
                Oracle.TargetPredatesOldestObservation.selector, oldestTimestamp, uint32(int32(target))
            )
        );
        oracle.observe(secondsAgos);

        oracle.advanceTime(5);

        secondsAgos[0] = 20;
        vm.expectRevert(
            abi.encodeWithSelector(
                Oracle.TargetPredatesOldestObservation.selector, oldestTimestamp, uint32(int32(target))
            )
        );
        oracle.observe(secondsAgos);
    }

    function testManyObservationsOldest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 14);
        assertEq(tickCumulative, -13);
        assertEq(secondsPerLiquidityCumulativeX128, 544451787073501541541399371890829138329);
    }

    function testManyObservationsOldestAfterTime(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);
        oracle.advanceTime(6);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 20);
        assertEq(tickCumulative, -13);
        assertEq(secondsPerLiquidityCumulativeX128, 544451787073501541541399371890829138329);
    }

    function testManyObservationsFetchManyValues(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);
        oracle.advanceTime(6);
        uint32[] memory secondsAgos = new uint32[](7);
        secondsAgos[0] = 20;
        secondsAgos[1] = 17;
        secondsAgos[2] = 13;
        secondsAgos[3] = 10;
        secondsAgos[4] = 5;
        secondsAgos[5] = 1;
        secondsAgos[6] = 0;
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            oracle.observe(secondsAgos);
        assertEq(tickCumulatives[0], -13);
        assertEq(secondsPerLiquidityCumulativeX128s[0], 544451787073501541541399371890829138329);
        assertEq(tickCumulatives[1], -31);
        assertEq(secondsPerLiquidityCumulativeX128s[1], 799663562264205389138930327464655296921);
        assertEq(tickCumulatives[2], -43);
        assertEq(secondsPerLiquidityCumulativeX128s[2], 1045423049484883168306923099498710116305);
        assertEq(tickCumulatives[3], -37);
        assertEq(secondsPerLiquidityCumulativeX128s[3], 1423514568285925905488450441089563684590);
        assertEq(tickCumulatives[4], -15);
        assertEq(secondsPerLiquidityCumulativeX128s[4], 2152691068830794041481396028443352709138);
        assertEq(tickCumulatives[5], 9);
        assertEq(secondsPerLiquidityCumulativeX128s[5], 2347138135642758877746181518404363115684);
        assertEq(tickCumulatives[6], 15);
        assertEq(secondsPerLiquidityCumulativeX128s[6], 2395749902345750086812377890894615717321);
    }

    function testGasAllOfLast20Seconds() public {
        setupOracleWithManyObservations(5);
        oracle.advanceTime(6);
        uint32[] memory secondsAgos = new uint32[](20);
        for (uint32 i = 0; i < 20; i++) {
            secondsAgos[i] = 20 - i;
        }
        snap("OracleObserveLast20Seconds", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testGasLatestEqual() public {
        setupOracleWithManyObservations(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("OracleObserveLatestEqual", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testGasLatestTransform() public {
        setupOracleWithManyObservations(5);
        oracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("OracleObserveLatestTransform", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testGasOldest() public {
        setupOracleWithManyObservations(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 14;
        snap("OracleObserveOldest", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testGasBetweenOldestAndOldestPlusOne() public {
        setupOracleWithManyObservations(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 13;
        snap("OracleObserveBetweenOldestAndOldestPlusOne", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testGasMiddle() public {
        setupOracleWithManyObservations(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 5;
        snap("OracleObserveMiddle", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracle() public {
        setupFullOracle();

        assertEq(oracle.cardinalityNext(), 65535);
        assertEq(oracle.cardinality(), 65535);
        assertEq(oracle.index(), 165);

        // can observe into the ordered portion with exact seconds ago
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulative) = observeSingle(oracle, 100 * 13);
        assertEq(tickCumulative, -27970560813);
        assertEq(secondsPerLiquidityCumulative, 60465049086512033878831623038233202591033);

        // can observe into the ordered portion with unexact seconds ago
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 100 * 13 + 5);
        assertEq(tickCumulative, -27970232823);
        assertEq(secondsPerLiquidityCumulative, 60465023149565257990964350912969670793706);

        // can observe at exactly the latest observation
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -28055903863);
        assertEq(secondsPerLiquidityCumulative, 60471787506468701386237800669810720099776);

        // can observe into the unordered portion of array at exact seconds ago
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 200 * 13);
        assertEq(tickCumulative, -27885347763);
        assertEq(secondsPerLiquidityCumulative, 60458300386499273141628780395875293027404);

        // can observe into the unordered portion of array at seconds ago between observations
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 200 * 13 + 5);
        assertEq(tickCumulative, -27885020273);
        assertEq(secondsPerLiquidityCumulative, 60458274409952896081377821330361274907140);

        // can observe the oldest observation
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 13 * 65534);
        assertEq(tickCumulative, -175890);
        assertEq(secondsPerLiquidityCumulative, 33974356747348039873972993881117400879779);

        // can observe at exactly the latest observation after some time passes
        oracle.advanceTime(5);
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 5);
        assertEq(tickCumulative, -28055903863);
        assertEq(secondsPerLiquidityCumulative, 60471787506468701386237800669810720099776);

        // can observe after the latest observation counterfactual
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 3);
        assertEq(tickCumulative, -28056035261);
        assertEq(secondsPerLiquidityCumulative, 60471797865298117996489508104462919730461);

        // can observe the oldest observation after time passes
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 13 * 65534 + 5);
        assertEq(tickCumulative, -175890);
        assertEq(secondsPerLiquidityCumulative, 33974356747348039873972993881117400879779);
    }

    function testFullOracleGasCostObserveZero() public {
        setupFullOracle();
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("FullOracleObserveZero", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserve200By13() public {
        setupFullOracle();
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 200 * 13;
        snap("FullOracleObserve200By13", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserve200By13Plus5() public {
        setupFullOracle();
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 200 * 13 + 5;
        snap("FullOracleObserve200By13Plus5", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserve0After5Seconds() public {
        setupFullOracle();
        oracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("FullOracleObserve0After5Seconds", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserve5After5Seconds() public {
        setupFullOracle();
        oracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 5;
        snap("FullOracleObserve5After5Seconds", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserveOldest() public {
        setupFullOracle();
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 13 * 65534;
        snap("FullOracleObserveOldest", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserveOldestAfter5Seconds() public {
        setupFullOracle();
        oracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 13 * 65534;
        snap("FullOracleObserveOldestAfter5Seconds", oracle.getGasCostOfObserve(secondsAgos));
    }

    // fixtures and helpers

    function observeSingle(OracleTest _initializedOracle, uint32 secondsAgo)
        internal
        view
        returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulative)
    {
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = secondsAgo;
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulatives) =
            _initializedOracle.observe(secondsAgos);
        return (tickCumulatives[0], secondsPerLiquidityCumulatives[0]);
    }

    function assertObservation(OracleTest _initializedOracle, uint64 idx, Oracle.Observation memory expected)
        internal
    {
        (uint32 blockTimestamp, int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128, bool initialized) =
            _initializedOracle.observations(idx);
        assertEq(blockTimestamp, expected.blockTimestamp);
        assertEq(tickCumulative, expected.tickCumulative);
        assertEq(secondsPerLiquidityCumulativeX128, expected.secondsPerLiquidityCumulativeX128);
        assertEq(initialized, expected.initialized);
    }

    function setupOracleWithManyObservations(uint32 startingTime) internal {
        oracle.initialize(OracleTest.InitializeParams({liquidity: 5, tick: -5, time: startingTime}));
        oracle.grow(5);
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 3, tick: 1, liquidity: 2}));
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 2, tick: -6, liquidity: 4}));
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 4, tick: -2, liquidity: 4}));
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 1, tick: -2, liquidity: 9}));
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 3, tick: 4, liquidity: 2}));
        oracle.update(OracleTest.UpdateParams({advanceTimeBy: 6, tick: 6, liquidity: 7}));
    }

    function setupFullOracle() internal {
        uint16 BATCH_SIZE = 300;
        oracle.initialize(
            OracleTest.InitializeParams({
                liquidity: 0,
                tick: 0,
                // Monday, October 5, 2020 9:00:00 AM GMT-05:00
                time: 1601906400
            })
        );

        uint16 cardinalityNext = oracle.cardinalityNext();
        while (cardinalityNext < 65535) {
            uint16 growTo = cardinalityNext + BATCH_SIZE < 65535 ? 65535 : cardinalityNext + BATCH_SIZE;
            oracle.grow(growTo);
            cardinalityNext = growTo;
        }

        for (int24 i = 0; i < 65535; i += int24(uint24(BATCH_SIZE))) {
            OracleTest.UpdateParams[] memory batch = new OracleTest.UpdateParams[](BATCH_SIZE);
            for (int24 j = 0; j < int24(uint24(BATCH_SIZE)); j++) {
                batch[uint24(j)] = OracleTest.UpdateParams({
                    advanceTimeBy: 13,
                    tick: -i - j,
                    liquidity: uint128(int128(i) + int128(j))
                });
            }
            oracle.batchUpdate(batch);
        }
    }
}
