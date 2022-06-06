// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {Hooks} from '../libraries/Hooks.sol';
import {FullMath} from '../libraries/FullMath.sol';
import {SafeCast} from '../libraries/SafeCast.sol';
import {BaseHook} from './base/BaseHook.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {IERC1155Receiver} from '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';

type Epoch is uint232;

library EpochLibrary {
    function equals(Epoch a, Epoch b) internal pure returns (bool) {
        return Epoch.unwrap(a) == Epoch.unwrap(b);
    }

    function unsafeIncrement(Epoch a) internal pure returns (Epoch) {
        unchecked {
            return Epoch.wrap(Epoch.unwrap(a) + 1);
        }
    }
}

contract LimitOrderHook is BaseHook {
    using SafeCast for uint256;
    using EpochLibrary for Epoch;

    error ZeroLiquidity();
    error InRange();
    error CrossedRange();
    error Filled();
    error NotFilled();
    error NotPoolManagerToken();

    event Place(
        address indexed owner,
        Epoch indexed epoch,
        IPoolManager.PoolKey key,
        int24 tickLower,
        bool zeroForOne,
        uint128 liquidity
    );

    event Fill(Epoch indexed epoch, IPoolManager.PoolKey key, int24 tickLower, bool zeroForOne);

    event Kill(
        address indexed owner,
        Epoch indexed epoch,
        IPoolManager.PoolKey key,
        int24 tickLower,
        bool zeroForOne,
        uint128 liquidity
    );

    event Withdraw(address indexed owner, Epoch indexed epoch, uint128 liquidity);

    Epoch private constant EPOCH_DEFAULT = Epoch.wrap(0);

    mapping(bytes32 => int24) public tickLowerLasts;
    Epoch public epochNext = Epoch.wrap(1);

    struct EpochInfo {
        bool filled;
        IERC20Minimal token0;
        IERC20Minimal token1;
        uint256 token0Total;
        uint256 token1Total;
        uint128 liquidityTotal;
        mapping(address => uint128) liquidity;
    }

    mapping(bytes32 => Epoch) public epochs;
    mapping(Epoch => EpochInfo) public epochInfos;

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

    function getTickLowerLast(IPoolManager.PoolKey memory key) public view returns (int24) {
        return tickLowerLasts[keccak256(abi.encode(key))];
    }

    function setTickLowerLast(IPoolManager.PoolKey memory key, int24 tickLower) private {
        tickLowerLasts[keccak256(abi.encode(key))] = tickLower;
    }

    function getEpoch(
        IPoolManager.PoolKey memory key,
        int24 tickLower,
        bool zeroForOne
    ) public view returns (Epoch) {
        return epochs[keccak256(abi.encode(key, tickLower, zeroForOne))];
    }

    function setEpoch(
        IPoolManager.PoolKey memory key,
        int24 tickLower,
        bool zeroForOne,
        Epoch epoch
    ) private {
        epochs[keccak256(abi.encode(key, tickLower, zeroForOne))] = epoch;
    }

    function getEpochLiquidity(Epoch epoch, address owner) external view returns (uint256) {
        return epochInfos[epoch].liquidity[owner];
    }

    function getTick(IPoolManager.PoolKey memory key) private view returns (int24 tick) {
        (, tick) = poolManager.getSlot0(key);
    }

    function getTickLower(int24 tick, int24 tickSpacing) private pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity
        return compressed * tickSpacing;
    }

    function afterInitialize(
        address,
        IPoolManager.PoolKey calldata key,
        uint160,
        int24 tick
    ) external override poolManagerOnly {
        setTickLowerLast(key, getTickLower(tick, key.tickSpacing));
    }

    function afterSwap(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        IPoolManager.BalanceDelta calldata
    ) external override poolManagerOnly {
        int24 tickLower = getTickLower(getTick(key), key.tickSpacing);
        int24 tickLowerLast = getTickLowerLast(key);
        if (tickLower == tickLowerLast) return;

        int24 lower;
        int24 upper;
        if (tickLower < tickLowerLast) {
            // the pool has moved "left", meaning it's traded token1 for token0,
            lower = tickLower + key.tickSpacing;
            upper = tickLowerLast;
        } else {
            // the pool has moved "right", meaning it's traded token0 for token1
            lower = tickLowerLast;
            upper = tickLower - key.tickSpacing;
        }

        // note that a zeroForOne swap means that the pool is actually gaining token0, so limit
        // order fills are the opposite of swap fills, hence the inversion below
        bool zeroForOne = !params.zeroForOne;
        for (; lower <= upper; lower += key.tickSpacing) {
            Epoch epoch = getEpoch(key, lower, zeroForOne);
            if (!epoch.equals(EPOCH_DEFAULT)) {
                EpochInfo storage epochInfo = epochInfos[epoch];

                epochInfo.filled = true;

                (uint256 amount0, uint256 amount1) = abi.decode(
                    poolManager.lock(
                        abi.encodeCall(this.lockAcquiredFill, (key, lower, -int256(uint256(epochInfo.liquidityTotal))))
                    ),
                    (uint256, uint256)
                );

                unchecked {
                    epochInfo.token0Total += amount0;
                    epochInfo.token1Total += amount1;
                }

                setEpoch(key, lower, zeroForOne, EPOCH_DEFAULT);

                emit Fill(epoch, key, lower, zeroForOne);
            }
        }

        setTickLowerLast(key, tickLower);
    }

    function lockAcquiredFill(
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        int256 liquidityDelta
    ) external selfOnly returns (uint256 amount0, uint256 amount1) {
        IPoolManager.BalanceDelta memory delta = poolManager.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: tickLower,
                tickUpper: tickLower + key.tickSpacing,
                liquidityDelta: liquidityDelta
            })
        );

        if (delta.amount0 < 0) poolManager.mint(key.token0, address(this), amount0 = uint256(-delta.amount0));
        if (delta.amount1 < 0) poolManager.mint(key.token1, address(this), amount1 = uint256(-delta.amount1));
    }

    function place(
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        bool zeroForOne,
        uint128 liquidity
    ) external onlyValidPools(key.hooks) {
        if (liquidity == 0) revert ZeroLiquidity();

        poolManager.lock(
            abi.encodeCall(this.lockAcquiredPlace, (key, tickLower, zeroForOne, int256(uint256(liquidity)), msg.sender))
        );

        EpochInfo storage epochInfo;
        Epoch epoch = getEpoch(key, tickLower, zeroForOne);
        if (epoch.equals(EPOCH_DEFAULT)) {
            unchecked {
                setEpoch(key, tickLower, zeroForOne, epoch = epochNext);
                // since epoch was just assigned the current value of epochNext,
                // this is equivalent to epochNext++, which is what's intended,
                // and it saves an SLOAD
                epochNext = epoch.unsafeIncrement();
            }
            epochInfo = epochInfos[epoch];
            epochInfo.token0 = key.token0;
            epochInfo.token1 = key.token1;
        } else {
            epochInfo = epochInfos[epoch];
        }

        unchecked {
            epochInfo.liquidityTotal += liquidity;
            epochInfo.liquidity[msg.sender] += liquidity;
        }

        emit Place(msg.sender, epoch, key, tickLower, zeroForOne, liquidity);
    }

    function lockAcquiredPlace(
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        bool zeroForOne,
        int256 liquidityDelta,
        address owner
    ) external selfOnly {
        IPoolManager.BalanceDelta memory delta = poolManager.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: tickLower,
                tickUpper: tickLower + key.tickSpacing,
                liquidityDelta: liquidityDelta
            })
        );

        if (delta.amount0 > 0) {
            if (delta.amount1 != 0) revert InRange();
            if (!zeroForOne) revert CrossedRange();
            // TODO use safeTransferFrom
            key.token0.transferFrom(owner, address(poolManager), uint256(delta.amount0));
            poolManager.settle(key.token0);
        } else {
            if (delta.amount0 != 0) revert InRange();
            if (zeroForOne) revert CrossedRange();
            // TODO use safeTransferFrom
            key.token1.transferFrom(owner, address(poolManager), uint256(delta.amount1));
            poolManager.settle(key.token1);
        }
    }

    function kill(
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        bool zeroForOne,
        address to
    ) external returns (uint256 amount0, uint256 amount1) {
        Epoch epoch = getEpoch(key, tickLower, zeroForOne);
        EpochInfo storage epochInfo = epochInfos[epoch];

        if (epochInfo.filled) revert Filled();

        uint128 liquidity = epochInfo.liquidity[msg.sender];
        if (liquidity == 0) revert ZeroLiquidity();
        delete epochInfo.liquidity[msg.sender];
        uint128 liquidityTotal = epochInfo.liquidityTotal;
        epochInfo.liquidityTotal = liquidityTotal - liquidity;

        uint256 amount0Fee;
        uint256 amount1Fee;
        (amount0, amount1, amount0Fee, amount1Fee) = abi.decode(
            poolManager.lock(
                abi.encodeCall(
                    this.lockAcquiredKill,
                    (key, tickLower, -int256(uint256(liquidity)), to, liquidity == liquidityTotal)
                )
            ),
            (uint256, uint256, uint256, uint256)
        );

        unchecked {
            epochInfo.token0Total += amount0Fee;
            epochInfo.token1Total += amount1Fee;
        }

        emit Kill(msg.sender, epoch, key, tickLower, zeroForOne, liquidity);
    }

    function lockAcquiredKill(
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        int256 liquidityDelta,
        address to,
        bool removingAllLiquidity
    )
        external
        selfOnly
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 amount0Fee,
            uint256 amount1Fee
        )
    {
        int24 tickUpper = tickLower + key.tickSpacing;

        // because `modifyPosition` includes not just principal value but also fees, we cannot allocate
        // the proceeds pro-rata. if we were to do so, users who have been in a limit order that's partially filled
        // could be unfairly diluted by a user sychronously placing then killing a limit order to skim off fees.
        // to prevent this, we allocate all fee revenue to remaining limit order placers, unless this is the last order.
        if (!removingAllLiquidity) {
            IPoolManager.BalanceDelta memory deltaFee = poolManager.modifyPosition(
                key,
                IPoolManager.ModifyPositionParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: 0})
            );

            if (deltaFee.amount0 < 0)
                poolManager.mint(key.token0, address(this), amount0Fee = uint256(-deltaFee.amount0));
            if (deltaFee.amount1 < 0)
                poolManager.mint(key.token1, address(this), amount1Fee = uint256(-deltaFee.amount1));
        }

        IPoolManager.BalanceDelta memory delta = poolManager.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta
            })
        );

        if (delta.amount0 < 0) poolManager.take(key.token0, to, amount0 = uint256(-delta.amount0));
        if (delta.amount1 < 0) poolManager.take(key.token1, to, amount1 = uint256(-delta.amount1));
    }

    function withdraw(Epoch epoch, address to) external returns (uint256 amount0, uint256 amount1) {
        EpochInfo storage epochInfo = epochInfos[epoch];

        if (!epochInfo.filled) revert NotFilled();

        uint128 liquidity = epochInfo.liquidity[msg.sender];
        if (liquidity == 0) revert ZeroLiquidity();
        delete epochInfo.liquidity[msg.sender];

        uint256 token0Total = epochInfo.token0Total;
        uint256 token1Total = epochInfo.token1Total;
        uint128 liquidityTotal = epochInfo.liquidityTotal;

        amount0 = FullMath.mulDiv(token0Total, liquidity, liquidityTotal);
        amount1 = FullMath.mulDiv(token1Total, liquidity, liquidityTotal);

        epochInfo.token0Total = token0Total - amount0;
        epochInfo.token1Total = token1Total - amount1;
        epochInfo.liquidityTotal = liquidityTotal - liquidity;

        poolManager.lock(
            abi.encodeCall(this.lockAcquiredWithdraw, (epochInfo.token0, epochInfo.token1, amount0, amount1, to))
        );

        emit Withdraw(msg.sender, epoch, liquidity);
    }

    function lockAcquiredWithdraw(
        IERC20Minimal token0,
        IERC20Minimal token1,
        uint256 token0Amount,
        uint256 token1Amount,
        address to
    ) external selfOnly {
        if (token0Amount > 0) {
            poolManager.safeTransferFrom(
                address(this),
                address(poolManager),
                uint256(uint160(address(token0))),
                token0Amount,
                ''
            );
            poolManager.take(token0, to, token0Amount);
        }
        if (token1Amount > 0) {
            poolManager.safeTransferFrom(
                address(this),
                address(poolManager),
                uint256(uint160(address(token1))),
                token1Amount,
                ''
            );
            poolManager.take(token1, to, token1Amount);
        }
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external view returns (bytes4) {
        if (msg.sender != address(poolManager)) revert NotPoolManagerToken();
        return IERC1155Receiver.onERC1155Received.selector;
    }
}
