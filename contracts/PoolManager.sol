// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Pool} from './libraries/Pool.sol';
import {Tick} from './libraries/Tick.sol';
import {SafeCast} from './libraries/SafeCast.sol';

import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {IPoolManagerUser} from './interfaces/callback/IPoolManagerUser.sol';
import {NoDelegateCall} from './NoDelegateCall.sol';
import {IPoolManager} from './interfaces/IPoolManager.sol';

/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, NoDelegateCall {
    using SafeCast for *;
    using Pool for *;

    /// @notice Represents the configuration for a fee
    struct FeeConfig {
        int24 tickSpacing;
        uint128 maxLiquidityPerTick;
    }

    // todo: can we make this documented in the interface
    mapping(bytes32 => Pool.State) public pools;
    mapping(uint24 => FeeConfig) public override configs;

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

    function _getPool(IPoolManager.PoolKey memory key) private view returns (Pool.State storage) {
        return pools[keccak256(abi.encode(key))];
    }

    /// @notice Initialize the state for a given pool ID
    function initialize(IPoolManager.PoolKey memory key, uint160 sqrtPriceX96) external override returns (int24 tick) {
        tick = _getPool(key).initialize(_blockTimestamp(), sqrtPriceX96);
    }

    /// @notice Increase the maximum number of stored observations for the pool's oracle
    function increaseObservationCardinalityNext(IPoolManager.PoolKey memory key, uint16 observationCardinalityNext)
        external
        override
        returns (uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew)
    {
        (observationCardinalityNextOld, observationCardinalityNextNew) = _getPool(key)
            .increaseObservationCardinalityNext(observationCardinalityNext);
    }

    /// @notice Represents the address that has currently locked the pool
    address public override lockedBy;

    /// @notice All the latest tracked balances of tokens
    mapping(IERC20Minimal => uint256) public override reservesOf;

    /// @notice Internal transient enumerable set
    uint256 public override tokensTouchedBloomFilter;
    IERC20Minimal[] public override tokensTouched;
    mapping(IERC20Minimal => int256) public override tokenDelta;

    /// @dev Used to make sure all actions within the lock function are wrapped in the lock acquisition. Note this has no gas overhead because it's inlined.
    modifier acquiresLock() {
        require(lockedBy == address(0));
        lockedBy = msg.sender;

        _;

        delete lockedBy;
    }

    function lock(bytes calldata data) external override acquiresLock {
        // the caller does everything in this callback, including paying what they owe
        require(IPoolManagerUser(msg.sender).lockAcquired(data), 'No data');

        for (uint256 i = 0; i < tokensTouched.length; i++) {
            require(tokenDelta[tokensTouched[i]] == 0, 'Not settled');
        }
        delete tokensTouchedBloomFilter;
        delete tokensTouched;
    }

    /// @dev Adds a token to a unique list of tokens that have been touched
    function _addTokenToSet(IERC20Minimal token) internal {
        // todo: is it cheaper to mstore `uint160(uint160(address(token)))` or cast everywhere it's used?
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

    function _accountDelta(IERC20Minimal token, int256 delta) internal {
        _addTokenToSet(token);
        tokenDelta[token] += delta;
    }

    /// @dev Accumulates a balance change to a map of token to balance changes
    function _accountPoolBalanceDelta(PoolKey memory key, Pool.BalanceDelta memory delta) internal {
        _accountDelta(key.token0, delta.amount0);
        _accountDelta(key.token1, delta.amount1);
    }

    modifier onlyLocker() {
        require(msg.sender == lockedBy, 'LOK');
        _;
    }

    /// @dev Mint some liquidity for the given pool
    function mint(IPoolManager.PoolKey memory key, IPoolManager.MintParams memory params)
        external
        override
        noDelegateCall
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

        _accountPoolBalanceDelta(key, delta);
    }

    /// @dev Mint some liquidity for the given pool
    function burn(IPoolManager.PoolKey memory key, IPoolManager.BurnParams memory params)
        external
        override
        noDelegateCall
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

        _accountPoolBalanceDelta(key, delta);
    }

    function swap(IPoolManager.PoolKey memory key, IPoolManager.SwapParams memory params)
        external
        override
        noDelegateCall
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

        _accountPoolBalanceDelta(key, delta);
    }

    /// @notice Called by the user to net out some value owed to the user
    /// @dev Can also be used as a mechanism for _free_ flash loans
    function take(
        IERC20Minimal token,
        address to,
        uint256 amount
    ) external override noDelegateCall onlyLocker {
        _accountDelta(token, amount.toInt256());
        token.transfer(to, amount);
    }

    /// @notice Called by the user to pay what is owed
    function settle(IERC20Minimal token) external override noDelegateCall onlyLocker {
        uint256 reservesBefore = reservesOf[token];
        IPoolManagerUser(msg.sender).settleCallback(token, tokenDelta[token]);
        reservesOf[token] = token.balanceOf(address(this));
        // subtraction must be safe
        _accountDelta(token, -(reservesOf[token] - reservesBefore).toInt256());
    }

    /// @notice Update the protocol fee for a given pool
    function setFeeProtocol(IPoolManager.PoolKey calldata key, uint8 feeProtocol)
        external
        override
        returns (uint8 feeProtocolOld)
    {
        return _getPool(key).setFeeProtocol(feeProtocol);
    }

    /// @notice Observe a past state of a pool
    function observe(IPoolManager.PoolKey calldata key, uint32[] calldata secondsAgos)
        external
        view
        override
        noDelegateCall
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        return _getPool(key).observe(_blockTimestamp(), secondsAgos);
    }

    /// @notice Get the snapshot of the cumulative values of a tick range
    function snapshotCumulativesInside(
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper
    ) external view override noDelegateCall returns (Pool.Snapshot memory) {
        return _getPool(key).snapshotCumulativesInside(tickLower, tickUpper, _blockTimestamp());
    }
}
