// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {Hooks} from '../libraries/Hooks.sol';
import {FullMath} from '../libraries/FullMath.sol';
import {BaseHook} from './base/BaseHook.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

contract LimitOrders is BaseHook {
    error GenericLockFailure();
    error ZeroLiquidity();
    error InRange();
    error NotImplemented();
    error InvalidLimitOrderType();

    int24 public tickLowerLast;

    uint256 public epoch;

    struct EpochInfo {
        uint128 liquidityTotal;
        // we must store the token addresses for safety
        IERC20Minimal token0;
        IERC20Minimal token1;
        uint256 token0Total;
        uint256 token1Total;
        mapping(address => uint128) liquidity;
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

    function getTick(IPoolManager.PoolKey memory key) private view returns (int24 tick) {
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
                    poolManager.lock(abi.encodeCall(this.lockAcquiredFill, (key, lower, tickEpoch)));
                    setEpoch(key, lower, zeroForOne, 0);
                }
            }
        }

        tickLowerLast = tickLower;
    }

    function place(
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        uint256 liquidity
    ) external onlyValidPools(key.hooks) returns (IPoolManager.BalanceDelta memory) {
        if (liquidity == 0) revert ZeroLiquidity();

        return
            abi.decode(
                poolManager.lock(
                    abi.encodeCall(this.lockAcquiredPlace, (msg.sender, key, tickLower, int256(liquidity)))
                ),
                (IPoolManager.BalanceDelta)
            );
    }

    function lockAcquiredPlace(
        address owner,
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        int256 liquidityDelta
    ) external selfOnly returns (IPoolManager.BalanceDelta memory) {
        int24 tick = getTick(key);
        bool zeroForOne = tick >= tickLower;

        uint256 tickEpoch = getEpoch(key, tickLower, zeroForOne);
        EpochInfo storage epochInfo;
        if (tickEpoch == 0) {
            setEpoch(key, tickLower, zeroForOne, tickEpoch = ++epoch);
            epochInfo = epochInfos[tickEpoch];
            epochInfo.token0 = key.token0;
            epochInfo.token1 = key.token1;
        } else {
            epochInfo = epochInfos[tickEpoch];
        }

        IPoolManager.BalanceDelta memory delta = poolManager.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: tickLower,
                tickUpper: tickLower + key.tickSpacing,
                liquidityDelta: liquidityDelta
            })
        );

        uint128 liquidity = uint128(uint256(liquidityDelta));
        // neither of the following can overflow by assumption
        unchecked {
            epochInfo.liquidityTotal += liquidity;
            epochInfo.liquidity[owner] += liquidity;
        }

        if (delta.amount0 > 0) {
            if (delta.amount1 != 0) revert InRange();
            key.token0.transferFrom(owner, address(poolManager), uint256(delta.amount0));
            poolManager.settle(key.token0);
        } else {
            if (delta.amount0 != 0) revert InRange();
            key.token1.transferFrom(owner, address(poolManager), uint256(delta.amount1));
            poolManager.settle(key.token1);
        }

        // emit event here

        return delta;
    }

    function lockAcquiredFill(
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        uint256 _epoch
    ) external selfOnly returns (IPoolManager.BalanceDelta memory) {
        EpochInfo storage epochInfo = epochInfos[_epoch];

        IPoolManager.BalanceDelta memory delta = poolManager.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: tickLower,
                tickUpper: tickLower + key.tickSpacing,
                liquidityDelta: -int256(uint256(epochInfo.liquidityTotal))
            })
        );

        uint256 amount0 = uint256(-delta.amount0);
        poolManager.mint(key.token0, address(this), amount0);
        epochInfo.token0Total += amount0;
        uint256 amount1 = uint256(-delta.amount1);
        poolManager.mint(key.token1, address(this), amount1);
        epochInfo.token1Total += amount1;

        // emit event here

        return delta;
    }

    function kill(
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        bool zeroForOne,
        address to
    ) external {
        uint256 tickEpoch = getEpoch(key, tickLower, zeroForOne);
        EpochInfo storage epochInfo = epochInfos[tickEpoch];

        uint128 liquidity = epochInfo.liquidity[msg.sender];
        if (liquidity == 0) revert ZeroLiquidity();
        delete epochInfo.liquidity[msg.sender];

        uint128 liquidityTotal = epochInfo.liquidityTotal;
        epochInfo.liquidityTotal = liquidityTotal - liquidity;

        poolManager.lock(
            abi.encodeCall(this.lockAcquiredKill, (tickEpoch, key, tickLower, to, -int256(uint256(liquidity))))
        );
    }

    function lockAcquiredKill(
        uint256 _epoch,
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        address to,
        int256 liquidityDelta
    ) external selfOnly returns (IPoolManager.BalanceDelta memory) {
        EpochInfo storage epochInfo = epochInfos[_epoch];

        // annoying, we have to collect fee revenue first, to prevent abuse
        // TODO if the caller is the only lp in the epoch, we don't have to do this
        // and should branch here
        IPoolManager.BalanceDelta memory feeDelta = poolManager.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: tickLower,
                tickUpper: tickLower + key.tickSpacing,
                liquidityDelta: 0
            })
        );

        IPoolManager.BalanceDelta memory delta = poolManager.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: tickLower,
                tickUpper: tickLower + key.tickSpacing,
                liquidityDelta: liquidityDelta
            })
        );

        // add the fee revenue to token totals for other LPs
        uint256 feeAmount0 = uint256(-feeDelta.amount0);
        poolManager.mint(key.token0, address(this), feeAmount0);
        epochInfo.token0Total += feeAmount0;
        uint256 feeAmount1 = uint256(-feeDelta.amount1);
        poolManager.mint(key.token1, address(this), feeAmount1);
        epochInfo.token1Total += feeAmount1;

        uint256[] memory ids = new uint256[](2);
        ids[0] = uint256(uint160(address(key.token0)));
        ids[1] = uint256(uint160(address(key.token1)));

        uint256[] memory amounts = new uint256[](2);
        ids[0] = uint256(-delta.amount0);
        ids[1] = uint256(-delta.amount1);

        // this burns the tokens and credits us with a delta
        poolManager.safeBatchTransferFrom(address(this), address(poolManager), ids, amounts, '');
        poolManager.take(key.token0, to, amounts[0]);
        poolManager.take(key.token1, to, amounts[1]);

        // emit event here

        return delta;
    }

    function withdraw(uint256 tickEpoch, address to) external {
        EpochInfo storage epochInfo = epochInfos[tickEpoch];
        uint128 liquidity = epochInfo.liquidity[msg.sender];
        if (liquidity == 0) revert ZeroLiquidity();
        delete epochInfo.liquidity[msg.sender];

        uint256 token0Total = epochInfo.token0Total;
        uint256 token1Total = epochInfo.token1Total;
        uint128 liquidityTotal = epochInfo.liquidityTotal;

        uint256 token0Amount = FullMath.mulDiv(token0Total, liquidity, liquidityTotal);
        uint256 token1Amount = FullMath.mulDiv(token1Total, liquidity, liquidityTotal);

        epochInfo.token0Total = token0Total - token0Amount;
        epochInfo.token1Total = token1Total - token1Amount;
        epochInfo.liquidityTotal = liquidityTotal - liquidity;

        poolManager.lock(
            abi.encodeCall(
                this.lockAcquiredWithdraw,
                (epochInfo.token0, epochInfo.token1, token0Amount, token1Amount, to)
            )
        );
    }

    function lockAcquiredWithdraw(
        IERC20Minimal token0,
        IERC20Minimal token1,
        uint256 token0Amount,
        uint256 token1Amount,
        address to
    ) external selfOnly {
        uint256[] memory ids = new uint256[](2);
        ids[0] = uint256(uint160(address(token0)));
        ids[1] = uint256(uint160(address(token1)));

        uint256[] memory amounts = new uint256[](2);
        ids[0] = token0Amount;
        ids[1] = token1Amount;

        // this burns the tokens and credits us with a delta
        poolManager.safeBatchTransferFrom(address(this), address(poolManager), ids, amounts, '');
        poolManager.take(token0, to, token0Amount);
        poolManager.take(token1, to, token1Amount);
    }
}
