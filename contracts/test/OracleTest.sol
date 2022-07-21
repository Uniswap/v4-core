// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {Oracle} from '../libraries/Oracle.sol';

contract OracleTest {
    using Oracle for Oracle.Observation[65535];

    Oracle.Observation[65535] public observations;

    int24 public tick;
    uint128 public liquidity;
    uint16 public index;
    uint16 public cardinality;
    uint16 public cardinalityNext;

    struct InitializeParams {
        uint32 time;
        int24 tick;
        uint128 liquidity;
    }

    function initialize(InitializeParams calldata params) external {
        require(cardinality == 0, 'already initialized');
        tick = params.tick;
        liquidity = params.liquidity;
        (cardinality, cardinalityNext) = observations.initialize();
    }

    struct UpdateParams {
        uint32 advanceTimeBy;
        int24 tick;
        uint128 liquidity;
    }

    // write an observation, then change tick and liquidity
    function update(UpdateParams calldata params) external {
        (index, cardinality) = observations.write(index, tick, liquidity, cardinality, cardinalityNext);
        tick = params.tick;
        liquidity = params.liquidity;
    }

    function batchUpdate(UpdateParams[] calldata params) external {
        // sload everything
        int24 _tick = tick;
        uint128 _liquidity = liquidity;
        uint16 _index = index;
        uint16 _cardinality = cardinality;
        uint16 _cardinalityNext = cardinalityNext;

        for (uint256 i = 0; i < params.length; i++) {
            (_index, _cardinality) = observations.write(
                _index,
                _tick,
                _liquidity,
                _cardinality,
                _cardinalityNext
            );
            _tick = params[i].tick;
            _liquidity = params[i].liquidity;
        }

        // sstore everything
        tick = _tick;
        liquidity = _liquidity;
        index = _index;
        cardinality = _cardinality;
    }

    function grow(uint16 _cardinalityNext) external {
        cardinalityNext = observations.grow(cardinalityNext, _cardinalityNext);
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        return observations.observe(secondsAgos, tick, index, liquidity, cardinality);
    }

    function getGasCostOfObserve(uint32[] calldata secondsAgos) external view returns (uint256) {
        (int24 _tick, uint128 _liquidity, uint16 _index) = (tick, liquidity, index);
        uint256 gasBefore = gasleft();
        observations.observe(secondsAgos, _tick, _index, _liquidity, cardinality);
        return gasBefore - gasleft();
    }
}
