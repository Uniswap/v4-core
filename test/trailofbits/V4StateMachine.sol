// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPoolManager} from "src/interfaces/IPoolManager.sol";

import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {PoolKey} from "src/types/PoolKey.sol";

import {LiquidityMath} from "src/libraries/LiquidityMath.sol";
import {LPFeeLibrary} from "src/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "src/libraries/ProtocolFeeLibrary.sol";
import {Pool} from "src/libraries/Pool.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {SwapMath} from "src/libraries/SwapMath.sol";
import {TickBitmap} from "src/libraries/TickBitmap.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {TransientStateLibrary} from "src/libraries/TransientStateLibrary.sol";

import {Deployers} from "test/utils/Deployers.sol";

import {PropertiesAsserts} from "test/trailofbits/PropertiesHelper.sol";

/// @notice This contract contains a limited reproduction of the v4 state machine.
/// Context: Some information in the v4 architecture is not directly accessible from any kind of 
/// solidity-based getter (example: the amount of LP fees collected for a given swap).
/// Since our harness is the only entrypoint for the system, we can cache every single liquidity
/// position, then reconstruct the internal tickInfo and tickBitmap for each pool
/// immediately before swapping.
/// We can then "simulate" the swap against our reconstructed tickInfo/tickBitmap, extracting
/// the values we need for verifying properties. 
/// In the future, this technique can be extended for modifyLiquidity and be used to verify 
/// reversion properties.
contract V4StateMachine is PropertiesAsserts, Deployers {
    using PoolIdLibrary for PoolKey;
    using ProtocolFeeLibrary for *;
    using TickBitmap for mapping(int16 => uint256);
    using TransientStateLibrary for IPoolManager;
    using SafeCast for *;
    using StateLibrary for IPoolManager;

    struct TickInfoUnpacked {
        uint128 liquidityGross;
        int128 liquidityNet;
    }

    struct TickDescr{
        int24 tick;
        int24 tickSpacing;
    }

    struct PositionInfo {
        uint128 liquidity;
        int24 tickLower;
        int24 tickUpper;
    }

    // This is used for storing the tickBitmap for all pools. It is deleted and rebuilt before every simulation.
    mapping(int16 => uint256) private TickBitmapProxy;
    // Used for deleting the TickBitmapProxy mapping
    TickDescr[] TickBitmapIndexes;

    // Used for reconstructing the tickInfo for all pools. It is deleted and rebuilt before every simulation.   
    mapping(int24 => TickInfoUnpacked) private TickInfos;
    mapping(int24 => bool) private TickInfoInitialized;
    // Used for deleting the TickInfos mapping
    int24[] private TickInfoIndexes;

    // a poolId lookup of all positions for the pool.
    // Includes positions that are cleared, they simply have 0 liquidity.
    // The LiquidityActionProps contract handles adding/updating liquidity positions.
    // In the future, consider moving the logic for updating positions into this class to improve decoupling.
    mapping(PoolId => PositionInfo[]) PoolPositions;

    // key is keccak(poolId, positionKey)
    // The LiquidityActionProps contract handles adding/updating liquidity positions.
    mapping(bytes32 => int) PositionInfoIndex;

    /// @notice This function is the main entrypoint for the simulated state machine.
   function _calculateExpectedLPAndProtocolFees(PoolKey memory pool, bool zeroForOne, int256 amount, uint256 priceLimit) internal returns (uint256, uint256) {
        _updateTickBitmapProxy(pool);

        // Most of following code is a near 1:1 reproduction of Pool.swap()
        uint256 feeGrowthGlobalX128;
        {
            (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = manager.getFeeGrowthGlobals(pool.toId());
            feeGrowthGlobalX128 = zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128;
        }

        Pool.SwapState memory state;
        uint160 curPrice;
        uint24 swapFee;
        uint24 protocolFee;
        {
            int24 curTick;
            uint24 protocolFeeRaw;
            uint24 lpFee;
            (curPrice, curTick, protocolFeeRaw, lpFee) = manager.getSlot0(pool.toId());
            state.amountSpecifiedRemaining = amount;
            state.amountCalculated = 0;
            state.sqrtPriceX96 = curPrice;
            state.tick = curTick;
            state.feeGrowthGlobalX128 = feeGrowthGlobalX128;
            state.liquidity = manager.getLiquidity(pool.toId());

            if(zeroForOne){
                protocolFee = protocolFeeRaw.getZeroForOneFee();
            } else {
                protocolFee = protocolFeeRaw.getOneForZeroFee();
            }

            if(protocolFee == 0) {
                swapFee = lpFee;
            } else {
                swapFee = uint16(protocolFee).calculateSwapFee(lpFee);
            }
        }

        {
            bool exactInput = amount < 0;
            if((swapFee == LPFeeLibrary.MAX_LP_FEE && !exactInput) || amount == 0) {
                return (0,0);
            }
        }

        if (zeroForOne) {
            if (priceLimit >= curPrice) {
                return (0,0);
            }
            if (priceLimit < TickMath.MIN_SQRT_PRICE) {
                return (0,0);
            }
        } else {
            if (priceLimit <= curPrice) {
                return (0,0);
            }
            if (priceLimit >= TickMath.MAX_SQRT_PRICE) {
                return (0,0);
            }
        }

        // pack into a swapinfo to save stack
        Pool.SwapParams memory swapInfo = Pool.SwapParams(
            pool.tickSpacing,
            zeroForOne,
            amount,
            uint160(priceLimit),
            0
        );
        return _calculateSteps(swapInfo, state, swapFee, pool.tickSpacing, protocolFee);
    }


    /// @notice Continuation of _calculateExpectedLPAndProtocolFees. Needed to save stack space.
    function _calculateSteps( Pool.SwapParams memory params, Pool.SwapState memory state, uint24 swapFee, int24 tickSpacing, uint24 protocolFee) private view returns (uint256, uint256) {
       Pool.StepComputations memory step;
       bool exactInput = params.amountSpecified < 0;
       uint256 feeForProtocol;
       uint256 feeForLp;
       while (!(state.amountSpecifiedRemaining == 0 || state.sqrtPriceX96 == params.sqrtPriceLimitX96)) {
            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) =
                TickBitmapProxy.nextInitializedTickWithinOneWord(state.tick, tickSpacing, params.zeroForOne);

            if (step.tickNext <= TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            }
            if (step.tickNext >= TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            step.sqrtPriceNextX96 = TickMath.getSqrtPriceAtTick(step.tickNext);

            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                SwapMath.getSqrtPriceTarget(params.zeroForOne, step.sqrtPriceNextX96, params.sqrtPriceLimitX96),
                state.liquidity,
                state.amountSpecifiedRemaining,
                swapFee
            );

            if (!exactInput) {
                unchecked {
                    state.amountSpecifiedRemaining -= step.amountOut.toInt256();
                }
                state.amountCalculated -= (step.amountIn + step.feeAmount).toInt256();
            } else {
                unchecked {
                    state.amountSpecifiedRemaining += (step.amountIn + step.feeAmount).toInt256();
                }
                state.amountCalculated += step.amountOut.toInt256();
            }
            if (protocolFee > 0) {
                unchecked {
                    // step.amountIn does not include the swap fee, as it's already been taken from it,
                    // so add it back to get the total amountIn and use that to calculate the amount of fees owed to the protocol
                    // this line cannot overflow due to limits on the size of protocolFee and params.amountSpecified
                    uint256 delta = (step.amountIn + step.feeAmount) * protocolFee / ProtocolFeeLibrary.PIPS_DENOMINATOR;
                    // subtract it from the total fee and add it to the protocol fee
                    //emit LogUint256("protocol fee delta", delta);
                    step.feeAmount -= delta;
                    feeForProtocol += delta;
                }
            }

            feeForLp += step.feeAmount;
            // skip fee growth calc, don't care
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // if the tick is initialized, run the tick transition
                if (step.initialized) {

                    int128 liquidityNet = TickInfos[step.tickNext].liquidityNet;
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    unchecked {
                        if (params.zeroForOne) liquidityNet = -liquidityNet;
                    }
                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }
                state.tick = params.zeroForOne ? step.tickNext - 1 : step.tickNext;
                
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtPrice(state.sqrtPriceX96);
            }
        }

        return (protocolFee,feeForLp);
    }

    /// @notice This code reproduces parts of Pool.modifyLiquidity and Pool.updateTick.
    /// Some of the logic is rewritten because we don't have to concern ourselves with
    /// liquidity removal. Every time this function is called, we're fully reconstructing the state.
    function _updateTickBitmapProxy(PoolKey memory pool) private  {
        _deleteTickBitmapProxy();
        _deleteTickInfos();

        PositionInfo[] storage positions = PoolPositions[pool.toId()];
        for(uint i=0; i<positions.length; i++) {
            PositionInfo memory position = positions[i];
            if (position.liquidity == 0) {
                continue;
            }
            if( !TickInfoInitialized[position.tickLower]) {
                TickInfoIndexes.push(position.tickLower);
                TickInfoInitialized[position.tickLower] = true;
                TickBitmapProxy.flipTick(position.tickLower, pool.tickSpacing);
                TickBitmapIndexes.push(TickDescr(position.tickLower,pool.tickSpacing));
                TickInfos[position.tickLower] = TickInfoUnpacked({
                    liquidityGross: 0,
                    liquidityNet: 0
                });
            }
            
            TickInfos[position.tickLower].liquidityGross += position.liquidity;
            TickInfos[position.tickLower].liquidityNet =  TickInfos[position.tickLower].liquidityNet + int128(position.liquidity);
   
            if( !TickInfoInitialized[position.tickUpper]) {
                TickInfoIndexes.push(position.tickUpper);
                TickInfoInitialized[position.tickUpper] = true;
                TickBitmapProxy.flipTick(position.tickUpper, pool.tickSpacing);
                TickBitmapIndexes.push(TickDescr(position.tickUpper,pool.tickSpacing));
                TickInfos[position.tickUpper] = TickInfoUnpacked({
                    liquidityGross: 0,
                    liquidityNet: 0
                });
            }
            TickInfos[position.tickUpper].liquidityGross += position.liquidity;
            TickInfos[position.tickUpper].liquidityNet =  TickInfos[position.tickUpper].liquidityNet - int128(position.liquidity);
        }
    }


    function _deleteTickBitmapProxy() private {
        for(uint i=0; i<TickBitmapIndexes.length; i++) {
            TickDescr memory tickDescr = TickBitmapIndexes[i];
            TickBitmapProxy.flipTick(tickDescr.tick, tickDescr.tickSpacing);
        }
        delete TickBitmapIndexes;
    }

    function _deleteTickInfos() private {
        for(uint i=0; i<TickInfoIndexes.length; i++) {
            delete TickInfos[TickInfoIndexes[i]];
            delete TickInfoInitialized[TickInfoIndexes[i]];
        }
        delete TickInfoIndexes;
    }

    /// @notice calculate the expected fee growth delta, accounting for overflow.
    /// This doesn't actually touch the state machine, but it makes more sense to have it herer than in ActionFuzzBase.
    function _calculateExpectedFeeGrowth(uint256 feeGrowthDeltaX128, uint256 prevFeeGrowthX128) internal returns (uint256) {
        // we could just do this as unchecked math, but it's nice to verify our assumptions.
        uint256 growthOverheadX128 = type(uint256).max - prevFeeGrowthX128;
        emit LogUint256("prev fee growth", prevFeeGrowthX128);
        emit LogUint256("growth overhead", growthOverheadX128);
        emit LogUint256("fee growth delta", feeGrowthDeltaX128);
        uint256 feeGrowthExpectedX128;
        if( feeGrowthDeltaX128 > growthOverheadX128){
            emit LogString("Fee growth is going to overflow");
            // overflow case
            feeGrowthExpectedX128 = feeGrowthDeltaX128 - growthOverheadX128 - 1;
        } else {
            emit LogString("Fee growth isn't overflowing");
            // normal case
            feeGrowthExpectedX128 = prevFeeGrowthX128 + feeGrowthDeltaX128;
        }
        return feeGrowthExpectedX128;
    }

}