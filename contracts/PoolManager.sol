// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Pool} from './libraries/Pool.sol';
import {Tick} from './libraries/Tick.sol';
import {SafeCast} from './libraries/SafeCast.sol';

import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {ILockCallback} from './interfaces/callback/ILockCallback.sol';

/// @notice Holds the state for all pools
contract PoolManager {
    using SafeCast for *;
    using Pool for *;

    /// @notice Returns the key for identifying a pool
    struct PoolKey {
        /// @notice The lower token of the pool, sorted numerically
        IERC20Minimal token0;
        /// @notice The higher token of the pool, sorted numerically
        IERC20Minimal token1;
        /// @notice The fee for the pool
        uint24 fee;
    }

    struct FeeConfig {
        int24 tickSpacing;
        uint128 maxLiquidityPerTick;
    }

    mapping(bytes32 => Pool.State) public pools;
    mapping(uint24 => FeeConfig) public configs;

    constructor() {
        _configure(100, 1);
        _configure(500, 10);
        _configure(3000, 60);
        _configure(10000, 200);
    }

    function _configure(uint24 fee, int24 tickSpacing) internal {
        require(tickSpacing > 0);
        require(configs[fee].tickSpacing == 0);
        configs[fee].tickSpacing = tickSpacing;
        configs[fee].maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(tickSpacing);
        // todo: emit event
    }

    /// @dev For mocking in unit tests
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    function _getPool(PoolKey memory key) private view returns (Pool.State storage) {
        return pools[keccak256(abi.encode(key))];
    }

    /// @notice Initialize the state for a given pool ID
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24) {
        return _getPool(key).initialize(_blockTimestamp(), sqrtPriceX96);
    }

    /// @notice Increase the maximum number of stored observations for the pool's oracle
    function increaseObservationCardinalityNext(PoolKey memory key, uint16 observationCardinalityNext)
        external
        returns (uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew)
    {
        (observationCardinalityNextOld, observationCardinalityNextNew) = _getPool(key)
            .increaseObservationCardinalityNext(observationCardinalityNext);
    }

    struct MintParams {
        // the address that will own the minted liquidity
        address recipient;
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        uint256 amount;
    }

    /// @notice Represents the address that has currently locked the pool
    address public lockedBy;

    /// @notice Internal transient enumerable set
    uint256 tokensTouchedBloomFilter;
    IERC20Minimal[] public tokensTouched;
    mapping(IERC20Minimal => int256) public tokenDelta;

    function lock() external {
        require(lockedBy == address(0));
        lockedBy = msg.sender;
        ILockCallback(msg.sender).lockAcquired();

        // todo: handle payment of the deltas

        for (uint256 i = 0; i < tokensTouched.length; i++) {
            delete tokenDelta[tokensTouched[i]];
        }
        delete tokensTouchedBloomFilter;
        delete tokensTouched;

        // delimiter to indicate where the lock is cleared
        delete lockedBy;
    }

    /// @dev Adds a token to a unique list of tokens that have been touched
    function _addTokenToSet(IERC20Minimal token) internal {
        // if the bloom filter doesn't hit, we know it's not in the set, push it
        if (tokensTouchedBloomFilter & uint160(uint160(address(token))) != uint160(uint160(address(token)))) {
            tokensTouched.push(token);
        } else {
            bool seen;
            for (uint256 i = 0; i < tokensTouched.length; i++) {
                if (seen = (tokensTouched[i] == token)) {
                    break;
                }
            }
            if (!seen) {
                tokensTouched.push(token);
            }
        }
        tokensTouchedBloomFilter |= uint160(uint160(address(token)));
    }

    /// @dev Accumulates a balance change to a map of token to balance changes
    function _accountDelta(PoolKey memory key, Pool.BalanceDelta memory delta) internal {
        _addTokenToSet(key.token0);
        _addTokenToSet(key.token1);
        tokenDelta[key.token0] += delta.amount0;
        tokenDelta[key.token1] += delta.amount1;
    }

    modifier onlyLocker() {
        require(msg.sender == lockedBy, 'LOK');
        _;
    }

    /// @dev Mint some liquidity for the given pool
    function mint(PoolKey memory key, MintParams memory params)
        external
        onlyLocker
        returns (Pool.BalanceDelta memory delta)
    {
        require(params.amount > 0);

        FeeConfig memory config = configs[key.fee];

        delta = _getPool(key).modifyPosition(
            Pool.ModifyPositionParams({
                owner: params.recipient,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: int256(uint256(params.amount)).toInt128(),
                time: _blockTimestamp(),
                maxLiquidityPerTick: config.maxLiquidityPerTick,
                tickSpacing: config.tickSpacing
            })
        );

        _accountDelta(key, delta);
    }

    struct BurnParams {
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // the reduction in liquidity to effect
        uint256 amount;
    }

    /// @dev Mint some liquidity for the given pool
    function burn(PoolKey memory key, BurnParams memory params)
        external
        onlyLocker
        returns (Pool.BalanceDelta memory delta)
    {
        require(params.amount > 0);

        FeeConfig memory config = configs[key.fee];

        delta = _getPool(key).modifyPosition(
            Pool.ModifyPositionParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: -int256(uint256(params.amount)).toInt128(),
                time: _blockTimestamp(),
                maxLiquidityPerTick: config.maxLiquidityPerTick,
                tickSpacing: config.tickSpacing
            })
        );

        _accountDelta(key, delta);
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    function swap(PoolKey memory key, SwapParams memory params)
        external
        onlyLocker
        returns (Pool.BalanceDelta memory delta)
    {
        FeeConfig memory config = configs[key.fee];

        delta = _getPool(key).swap(
            Pool.SwapParams({
                time: _blockTimestamp(),
                fee: key.fee,
                tickSpacing: config.tickSpacing,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        _accountDelta(key, delta);
    }

    /// @notice Update the protocol fee for a given pool
    function setFeeProtocol(PoolKey calldata key, uint8 feeProtocol) external returns (uint8 feeProtocolOld) {
        return _getPool(key).setFeeProtocol(feeProtocol);
    }

    /// @notice Observe a past state of a pool
    function observe(PoolKey calldata key, uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        return _getPool(key).observe(_blockTimestamp(), secondsAgos);
    }

    /// @notice Get the snapshot of the cumulative values of a tick range
    function snapshotCumulativesInside(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (Pool.Snapshot memory) {
        return _getPool(key).snapshotCumulativesInside(tickLower, tickUpper, _blockTimestamp());
    }
}
