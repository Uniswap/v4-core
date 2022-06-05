pragma solidity ^0.8.15;

import {Test} from 'forge-std/Test.sol';
import {Vm} from 'forge-std/Vm.sol';
import {IPoolManager} from '../../contracts/interfaces/IPoolManager.sol';
import {Pool} from '../../contracts/libraries/Pool.sol';
import {Position} from '../../contracts/libraries/Position.sol';
import {TickMath} from '../../contracts/libraries/TickMath.sol';
import {Random} from './utils/Random.sol';
import {Num} from './utils/Num.sol';
import {PoolSimulation} from './utils/PoolSimulation.sol';

contract PoolTest is Test {
    using Pool for Pool.State;
    using Random for Random.Rand;
    using Num for uint256;

    Pool.State state;

    function testInitialize(uint160 sqrtPriceX96, uint8 protocolFee) public {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO || sqrtPriceX96 >= TickMath.MAX_SQRT_RATIO) {
            vm.expectRevert(TickMath.InvalidSqrtRatio.selector);
            state.initialize(sqrtPriceX96, protocolFee);
        } else {
            state.initialize(sqrtPriceX96, protocolFee);
            assertEq(state.slot0.sqrtPriceX96, sqrtPriceX96);
            assertEq(state.slot0.protocolFee, protocolFee);
            assertEq(state.slot0.tick, TickMath.getTickAtSqrtRatio(sqrtPriceX96));
            assertLt(state.slot0.tick, TickMath.MAX_TICK);
            assertGt(state.slot0.tick, TickMath.MIN_TICK - 1);
        }
    }

    function boundTickSpacing(int24 unbound) private pure returns (int24) {
        int24 tickSpacing = unbound;
        if (tickSpacing < 0) {
            tickSpacing -= type(int24).min;
        }
        return (tickSpacing % 32767) + 1;
    }

    function testBoundTickSpacing(int24 tickSpacing) external {
        int24 bound = boundTickSpacing(tickSpacing);
        assertGt(bound, 0);
        assertLt(bound, 32768);
    }

    function testRandomTick(uint256 seed, uint128 salt) external {
        Random.Rand memory rand = Random.Rand(seed, salt);
        int24 spacing = rand.tickSpacing();
        int24 bound = rand.tick(spacing);
        assertGe(bound, TickMath.MIN_TICK);
        assertLe(bound, TickMath.MAX_TICK);
    }

    function testModifyPosition(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tickSpacing
    ) public {
        tickSpacing = boundTickSpacing(tickSpacing);

        testInitialize(sqrtPriceX96, 0);

        if (tickLower >= tickUpper) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TicksMisordered.selector, tickLower, tickUpper));
        } else if (tickLower < TickMath.MIN_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickLowerOutOfBounds.selector, tickLower));
        } else if (tickUpper > TickMath.MAX_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickUpperOutOfBounds.selector, tickUpper));
        } else if (liquidityDelta < 0) {
            vm.expectRevert(abi.encodeWithSignature('Panic(uint256)', 0x11));
        } else if (liquidityDelta == 0) {
            vm.expectRevert(Position.CannotUpdateEmptyPosition.selector);
        } else if (liquidityDelta > int128(Pool.tickSpacingToMaxLiquidityPerTick(tickSpacing))) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickLiquidityOverflow.selector, tickLower));
        } else if (tickLower % tickSpacing != 0 || tickUpper % tickSpacing != 0) {
            vm.expectRevert();
        }

        state.modifyPosition(
            Pool.ModifyPositionParams({
                owner: address(this),
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                tickSpacing: tickSpacing
            })
        );
    }

    /// Test random set of modifyPosition and swap calls
    /// ensuring that all positions can be closed at the end
    function testRandomAddAndSwap(uint256 seed, uint256 numActions) public {
        Random.Rand memory rand = Random.Rand(seed, 0);
        // can increase max numActions at cost of test suite runtime
        numActions = uint8(numActions.bound(1, 16));
        uint160 sqrtPrice = rand.sqrtPrice();
        int24 tickSpacing = rand.tickSpacing();
        state.initialize(sqrtPrice, 0);

        Pool.ModifyPositionParams[] memory positions = new Pool.ModifyPositionParams[](numActions);

        for (uint256 i = 0; i < numActions; i++) {
            uint8 action = uint8(rand.u256().bound(0, 2));
            if (action == 0) {
                // add liquidity
                Pool.ModifyPositionParams memory params = PoolSimulation.addLiquidity(
                    state,
                    rand,
                    tickSpacing,
                    address(this)
                );
                positions[i] = params;
                state.modifyPosition(params);
            } else if (action == 1) {
                // swap
                state.swap(PoolSimulation.swap(state, rand, tickSpacing));
            }
        }

        for (uint256 i = 0; i < numActions; i++) {
            Pool.ModifyPositionParams memory position = positions[i];
            // some indices will be empty if they were used for another action
            if (position.liquidityDelta != 0) {
                position.liquidityDelta = -position.liquidityDelta;
                state.modifyPosition(position);
            }
        }
    }
}
