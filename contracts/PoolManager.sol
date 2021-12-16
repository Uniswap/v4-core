// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Pool} from './libraries/Pool.sol';
import {Tick} from './libraries/Tick.sol';
import {SafeCast} from './libraries/SafeCast.sol';

import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {NoDelegateCall} from './NoDelegateCall.sol';
import {IPoolManager} from './interfaces/IPoolManager.sol';
import {ILockCallback} from './interfaces/callback/ILockCallback.sol';
import {BalanceDelta} from './interfaces/shared.sol';

/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, NoDelegateCall {
    using SafeCast for *;

    /// @notice Represents the address that has currently locked the pool
    address public override lockedBy;

    /// @notice All the latest tracked balances of tokens
    mapping(IERC20Minimal => uint256) public override reservesOf;

    /// @notice Internal transient enumerable set
    IERC20Minimal[] public override tokensTouched;
    struct PositionAndDelta {
        uint8 slot;
        int248 delta;
    }
    mapping(IERC20Minimal => PositionAndDelta) public override tokenDelta;

    function lock(bytes calldata data) external override returns (bytes memory result) {
        require(lockedBy == address(0));
        lockedBy = msg.sender;

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = ILockCallback(msg.sender).lockAcquired(data);

        unchecked {
            for (uint256 i = 0; i < tokensTouched.length; i++) {
                require(tokenDelta[tokensTouched[i]].delta == 0, 'Not settled');
                delete tokenDelta[tokensTouched[i]];
            }
        }
        delete tokensTouched;
        delete lockedBy;
    }

    /// @dev Adds a token to a unique list of tokens that have been touched
    function _addTokenToSet(IERC20Minimal token) internal returns (uint8 slot) {
        uint256 len = tokensTouched.length;
        if (len == 0) {
            tokensTouched.push(token);
            return 0;
        }

        PositionAndDelta storage pd = tokenDelta[token];
        slot = pd.slot;

        if (slot == 0 && tokensTouched[slot] != token) {
            require(len < type(uint8).max);
            slot = uint8(len);
            pd.slot = slot;
            tokensTouched.push(token);
        }
    }

    function _accountDelta(IERC20Minimal token, int256 delta) internal {
        if (delta == 0) return;
        _addTokenToSet(token);
        tokenDelta[token].delta += int248(delta);
    }

    /// @dev Accumulates a balance change to a map of token to balance changes
    function _accountPoolBalanceDelta(IPoolManager.Pair memory pair, BalanceDelta memory delta) internal {
        _accountDelta(pair.token0, delta.amount0);
        _accountDelta(pair.token1, delta.amount1);
    }

    modifier onlyByLocker() {
        require(msg.sender == lockedBy, 'LOK');
        _;
    }

    /// @dev Mint some liquidity for the given pool
    function modifyPosition(IPoolManager.PoolKey memory key, bytes memory data)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta memory delta)
    {
        delta = key.poolImplementation.modifyPosition(msg.sender, key.pair, data);

        _accountPoolBalanceDelta(key.pair, delta);
    }

    function swap(IPoolManager.PoolKey memory key, bytes memory data)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta memory delta)
    {
        delta = key.poolImplementation.swap(msg.sender, key.pair, data);

        _accountPoolBalanceDelta(key.pair, delta);
    }

    /// @notice Called by the user to net out some value owed to the user
    /// @dev Can also be used as a mechanism for _free_ flash loans
    function take(
        IERC20Minimal token,
        address to,
        uint256 amount
    ) external override noDelegateCall onlyByLocker {
        _accountDelta(token, amount.toInt256());
        reservesOf[token] -= amount;
        token.transfer(to, amount);
    }

    /// @notice Called by the user to pay what is owed
    function settle(IERC20Minimal token) external override noDelegateCall onlyByLocker returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[token];
        reservesOf[token] = token.balanceOf(address(this));
        paid = reservesOf[token] - reservesBefore;
        // subtraction must be safe
        _accountDelta(token, -(paid.toInt256()));
    }
}
