// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {Hooks} from '../libraries/Hooks.sol';
import {BaseHook} from './base/BaseHook.sol';

contract LimitOrders is BaseHook {
    error ZeroLiquidity();
    error InRange();
    error NotImplemented();

    int24 public tickLowerLast;

    uint256 public epoch;

    struct EpochInfo {
        uint128 liquidityTotal;
        uint256 token0;
        uint256 token1;
        mapping(address => uint256) liquidity;
    }

    mapping(bytes32 => uint256) private epochs;
    mapping(uint256 => EpochInfo) public epochInfos;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        Hooks.validateHookAddress(
            this,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: true,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false
            })
        );
    }

    function getEpoch(
        IPoolManager.PoolKey memory key,
        int24 tickLower,
        bool zeroForOne
    ) public view returns (uint256) {
        return epochs[keccak256(abi.encode(key, tickLower, zeroForOne))];
    }

    function setEpoch(
        IPoolManager.PoolKey memory key,
        int24 tickLower,
        bool zeroForOne,
        uint256 epochToSet
    ) private {
        epochs[keccak256(abi.encode(key, tickLower, zeroForOne))] = epochToSet;
    }

    function getTick(IPoolManager.PoolKey calldata key) private view returns (int24 tick) {
        (, tick) = poolManager.getSlot0(key);
    }

    function getTickLower(int24 tick, int24 tickSpacing) private pure returns (int24 tickLower) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity
        tickLower = compressed * tickSpacing;
    }

    function afterInitialize(
        address,
        IPoolManager.PoolKey calldata key,
        uint160,
        int24 tick
    ) external override poolManagerOnly {
        tickLowerLast = getTickLower(tick, key.tickSpacing);
    }

    struct FillData {
        IPoolManager.PoolKey key;
        int24 tickLower;
        int256 liquidityDelta;
        bool zeroForOne;
    }

    function afterSwap(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external override poolManagerOnly {
        int24 tickLower = getTickLower(getTick(key), key.tickSpacing);

        if (tickLower == tickLowerLast) return;

        int24 lower;
        int24 upper;
        bool zeroForOne;
        unchecked {
            if (tickLower < tickLowerLast) {
                lower = tickLower + key.tickSpacing;
                upper = tickLowerLast;
                // we've moved left, meaning we've traded token1 for token0
                zeroForOne = false;
            } else {
                lower = tickLowerLast;
                upper = tickLower - key.tickSpacing;
                // we've moved right, meaning we've traded token0 for token1
                zeroForOne = true;
            }
        }

        unchecked {
            for (; lower <= upper; lower += key.tickSpacing) {
                uint256 tickEpoch = getEpoch(key, lower, zeroForOne);
                if (epoch != 0) {
                    poolManager.lock(
                        abi.encode(
                            FillData({
                                key: key,
                                tickLower: tickLower,
                                liquidityDelta: -int256(uint256(epochInfos[tickEpoch].liquidityTotal)),
                                zeroForOne: zeroForOne
                            })
                        )
                    );
                    setEpoch(key, tickLower, zeroForOne, 0);
                }
            }
        }

        tickLowerLast = tickLower;
    }

    struct PlaceData {
        address owner;
        IPoolManager.PoolKey key;
        int24 tickLower;
        int256 liquidityDelta;
        bool zeroForOne;
    }

    function place(
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        uint128 liquidity
    ) external onlyValidPools(key.hooks) returns (IPoolManager.BalanceDelta memory) {
        if (liquidity == 0) revert ZeroLiquidity();

        int24 tick = getTick(key);

        return
            abi.decode(
                poolManager.lock(
                    abi.encode(
                        PlaceData({
                            owner: msg.sender,
                            key: key,
                            tickLower: tickLower,
                            liquidityDelta: int256(uint256(liquidity)),
                            zeroForOne: tick >= tickLower
                        })
                    )
                ),
                (IPoolManager.BalanceDelta)
            );
    }

    function lockAcquired(bytes calldata rawData) external poolManagerOnly returns (bytes memory) {
        if (rawData.length == 123) {
            PlaceData memory data = abi.decode(rawData, (PlaceData));

            uint256 tickEpoch = getEpoch(data.key, data.tickLower, false);
            if (tickEpoch == 0) {
                setEpoch(data.key, data.tickLower, data.zeroForOne, tickEpoch = ++epoch);
            }

            IPoolManager.BalanceDelta memory delta = poolManager.modifyPosition(
                data.key,
                IPoolManager.ModifyPositionParams({
                    tickLower: data.tickLower,
                    tickUpper: data.tickLower + data.key.tickSpacing,
                    liquidityDelta: data.liquidityDelta
                })
            );

            EpochInfo storage epochInfo = epochInfos[tickEpoch];
            uint128 liquidity = uint128(uint256(data.liquidityDelta));
            // neither of the following can overflow by assumption
            unchecked {
                epochInfo.liquidityTotal += liquidity;
                epochInfo.liquidity[data.owner] += liquidity;
            }

            if (delta.amount0 > 0) {
                if (delta.amount1 != 0) revert InRange();
                data.key.token0.transferFrom(data.owner, address(poolManager), uint256(delta.amount0));
                poolManager.settle(data.key.token0);
            } else {
                if (delta.amount0 != 0) revert InRange();
                data.key.token1.transferFrom(data.owner, address(poolManager), uint256(delta.amount1));
                poolManager.settle(data.key.token1);
            }

            // emit event here for tracking

            return abi.encode(delta);
        } else {
            revert NotImplemented();
        }
    }
}
