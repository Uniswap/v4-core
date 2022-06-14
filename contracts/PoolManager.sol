// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TransferHelper} from './libraries/TransferHelper.sol';
import {Hooks} from './libraries/Hooks.sol';
import {Pool} from './libraries/Pool.sol';
import {Tick} from './libraries/Tick.sol';
import {SafeCast} from './libraries/SafeCast.sol';
import {Position} from './libraries/Position.sol';
import {TransferHelper} from './libraries/TransferHelper.sol';

import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {NoDelegateCall} from './NoDelegateCall.sol';
import {Owned} from './Owned.sol';
import {IHooks} from './interfaces/IHooks.sol';
import {IProtocolFeeController} from './interfaces/IProtocolFeeController.sol';
import {IPoolManager} from './interfaces/IPoolManager.sol';
import {ILockCallback} from './interfaces/callback/ILockCallback.sol';

import {ERC1155} from '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import {IERC1155Receiver} from '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';
import {PoolId} from './libraries/PoolId.sol';

/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, Owned, NoDelegateCall, ERC1155, IERC1155Receiver {
    using PoolId for PoolKey;
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;
    using Position for mapping(bytes32 => Position.Info);
    using TransferHelper for IERC20Minimal;

    /// @inheritdoc IPoolManager
    int24 public constant override MAX_TICK_SPACING = type(int16).max;

    /// @inheritdoc IPoolManager
    int24 public constant override MIN_TICK_SPACING = 1;

    mapping(bytes32 => Pool.State) public pools;

    mapping(IERC20Minimal => uint256) public override protocolFeesAccrued;
    IProtocolFeeController public protocolFeeController;

    uint256 private immutable controllerGasLimit;

    constructor(uint256 _controllerGasLimit) ERC1155('') {
        controllerGasLimit = _controllerGasLimit;
    }

    function getPoolId(PoolKey calldata key) external pure returns (bytes32) {
        return key.toId();
    }

    function _getPool(PoolKey memory key) private view returns (Pool.State storage) {
        return pools[key.toId()];
    }

    /// @inheritdoc IPoolManager
    function getSlot0(bytes32 id)
        external
        view
        override
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint8 protocolFee
        )
    {
        Pool.Slot0 memory slot0 = pools[id].slot0;

        return (slot0.sqrtPriceX96, slot0.tick, slot0.protocolFee);
    }

    /// @inheritdoc IPoolManager
    function getLiquidity(bytes32 id) external view override returns (uint128 liquidity) {
        return pools[id].liquidity;
    }

    /// @inheritdoc IPoolManager
    function getLiquidity(
        bytes32 id,
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) external view override returns (uint128 liquidity) {
        return pools[id].positions.get(owner, tickLower, tickUpper).liquidity;
    }

    /// @inheritdoc IPoolManager
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external override returns (int24 tick) {
        // see TickBitmap.sol for overflow conditions that can arise from tick spacing being too large
        if (key.tickSpacing > MAX_TICK_SPACING) revert TickSpacingTooLarge();
        if (key.tickSpacing < MIN_TICK_SPACING) revert TickSpacingTooSmall();
        if (!key.hooks.isValidHookAddress()) revert Hooks.HookAddressNotValid(address(key.hooks));

        if (key.hooks.shouldCallBeforeInitialize()) {
            if (key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96) != IHooks.beforeInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        bytes32 id = key.toId();
        tick = pools[id].initialize(sqrtPriceX96, fetchPoolProtocolFee(id));

        if (key.hooks.shouldCallAfterInitialize()) {
            if (key.hooks.afterInitialize(msg.sender, key, sqrtPriceX96, tick) != IHooks.afterInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc IPoolManager
    mapping(IERC20Minimal => uint256) public override reservesOf;

    /// @inheritdoc IPoolManager
    address[] public override lockedBy;

    /// @inheritdoc IPoolManager
    function lockedByLength() external view returns (uint256) {
        return lockedBy.length;
    }

    /// @member index The index in the tokensTouched array where the token is found
    /// @member delta The delta that is owed for that particular token
    struct IndexAndDelta {
        uint8 index;
        int248 delta;
    }

    /// @member tokensTouched The tokens that have been touched by this locker
    /// @member tokenDelta The amount owed to the locker (positive) or owed to the pool (negative) of the token
    struct LockState {
        IERC20Minimal[] tokensTouched;
        mapping(IERC20Minimal => IndexAndDelta) tokenDelta;
    }

    /// @dev Represents the state of the locker at the given index. Each locker must have net 0 tokens owed before
    /// releasing their lock. Note this is private because the nested mappings cannot be exposed as a public variable.
    mapping(uint256 => LockState) private lockStates;

    /// @inheritdoc IPoolManager
    function getTokensTouchedLength(uint256 id) external view returns (uint256) {
        return lockStates[id].tokensTouched.length;
    }

    /// @inheritdoc IPoolManager
    function getTokensTouched(uint256 id, uint256 index) external view returns (IERC20Minimal) {
        return lockStates[id].tokensTouched[index];
    }

    /// @inheritdoc IPoolManager
    function getTokenDelta(uint256 id, IERC20Minimal token) external view returns (uint8 index, int248 delta) {
        IndexAndDelta storage indexAndDelta = lockStates[id].tokenDelta[token];
        (index, delta) = (indexAndDelta.index, indexAndDelta.delta);
    }

    /// @inheritdoc IPoolManager
    function lock(bytes calldata data) external override returns (bytes memory result) {
        uint256 id = lockedBy.length;
        lockedBy.push(msg.sender);

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = ILockCallback(msg.sender).lockAcquired(data);

        unchecked {
            LockState storage lockState = lockStates[id];
            uint256 numTokensTouched = lockState.tokensTouched.length;
            for (uint256 i; i < numTokensTouched; i++) {
                IERC20Minimal token = lockState.tokensTouched[i];
                IndexAndDelta storage indexAndDelta = lockState.tokenDelta[token];
                if (indexAndDelta.delta != 0) revert TokenNotSettled(token, indexAndDelta.delta);
                delete lockState.tokenDelta[token];
            }
            delete lockState.tokensTouched;
        }

        lockedBy.pop();
    }

    /// @dev Adds a token to a unique list of tokens that have been touched
    function _addTokenToSet(IERC20Minimal token) internal returns (uint8 index) {
        LockState storage lockState = lockStates[lockedBy.length - 1];
        uint256 numTokensTouched = lockState.tokensTouched.length;
        if (numTokensTouched == 0) {
            lockState.tokensTouched.push(token);
            return 0;
        }

        IndexAndDelta storage indexAndDelta = lockState.tokenDelta[token];
        index = indexAndDelta.index;

        if (index == 0 && lockState.tokensTouched[index] != token) {
            if (numTokensTouched >= type(uint8).max) revert MaxTokensTouched();
            index = uint8(numTokensTouched);
            indexAndDelta.index = index;
            lockState.tokensTouched.push(token);
        }
    }

    function _accountDelta(IERC20Minimal token, int256 delta) internal {
        if (delta == 0) return;
        _addTokenToSet(token);
        lockStates[lockedBy.length - 1].tokenDelta[token].delta += delta.toInt248();
    }

    /// @dev Accumulates a balance change to a map of token to balance changes
    function _accountPoolBalanceDelta(PoolKey memory key, IPoolManager.BalanceDelta memory delta) internal {
        _accountDelta(key.token0, delta.amount0);
        _accountDelta(key.token1, delta.amount1);
    }

    modifier onlyByLocker() {
        address locker = lockedBy[lockedBy.length - 1];
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    /// @inheritdoc IPoolManager
    function modifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (IPoolManager.BalanceDelta memory delta)
    {
        if (key.hooks.shouldCallBeforeModifyPosition()) {
            if (key.hooks.beforeModifyPosition(msg.sender, key, params) != IHooks.beforeModifyPosition.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        delta = _getPool(key).modifyPosition(
            Pool.ModifyPositionParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.tickSpacing
            })
        );

        _accountPoolBalanceDelta(key, delta);

        if (key.hooks.shouldCallAfterModifyPosition()) {
            if (key.hooks.afterModifyPosition(msg.sender, key, params, delta) != IHooks.afterModifyPosition.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc IPoolManager
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (IPoolManager.BalanceDelta memory delta)
    {
        if (key.hooks.shouldCallBeforeSwap()) {
            if (key.hooks.beforeSwap(msg.sender, key, params) != IHooks.beforeSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        uint256 feeForProtocol;
        (delta, feeForProtocol) = _getPool(key).swap(
            Pool.SwapParams({
                fee: key.fee,
                tickSpacing: key.tickSpacing,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        _accountPoolBalanceDelta(key, delta);
        // the fee is on the input token

        unchecked {
            if (feeForProtocol > 0) protocolFeesAccrued[params.zeroForOne ? key.token0 : key.token1] += feeForProtocol;
        }

        if (key.hooks.shouldCallAfterSwap()) {
            if (key.hooks.afterSwap(msg.sender, key, params, delta) != IHooks.afterSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc IPoolManager
    function donate(
        PoolKey memory key,
        uint256 amount0,
        uint256 amount1
    ) external override noDelegateCall onlyByLocker returns (IPoolManager.BalanceDelta memory delta) {
        if (key.hooks.shouldCallBeforeDonate()) {
            if (key.hooks.beforeDonate(msg.sender, key, amount0, amount1) != IHooks.beforeDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        delta = _getPool(key).donate(amount0, amount1);

        _accountPoolBalanceDelta(key, delta);

        if (key.hooks.shouldCallAfterDonate()) {
            if (key.hooks.afterDonate(msg.sender, key, amount0, amount1) != IHooks.afterDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc IPoolManager
    function take(
        IERC20Minimal token,
        address to,
        uint256 amount
    ) external override noDelegateCall onlyByLocker {
        _accountDelta(token, amount.toInt256());
        reservesOf[token] -= amount;
        token.safeTransfer(to, amount);
    }

    /// @inheritdoc IPoolManager
    function mint(
        IERC20Minimal token,
        address to,
        uint256 amount
    ) external override noDelegateCall onlyByLocker {
        _accountDelta(token, amount.toInt256());
        _mint(to, uint256(uint160(address(token))), amount, '');
    }

    /// @inheritdoc IPoolManager
    function settle(IERC20Minimal token) external override noDelegateCall onlyByLocker returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[token];
        reservesOf[token] = token.balanceOf(address(this));
        paid = reservesOf[token] - reservesBefore;
        // subtraction must be safe
        _accountDelta(token, -(paid.toInt256()));
    }

    function _burnAndAccount(IERC20Minimal token, uint256 amount) internal {
        _burn(address(this), uint256(uint160(address((token)))), amount);
        _accountDelta(IERC20Minimal(token), -(amount.toInt256()));
    }

    function onERC1155Received(
        address,
        address,
        uint256 id,
        uint256 value,
        bytes calldata
    ) external returns (bytes4) {
        if (msg.sender != address(this)) revert NotPoolManagerToken();
        _burnAndAccount(IERC20Minimal(address(uint160(id))), value);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata
    ) external returns (bytes4) {
        if (msg.sender != address(this)) revert NotPoolManagerToken();
        // unchecked to save gas on incrementations of i
        unchecked {
            for (uint256 i; i < ids.length; i++) {
                _burnAndAccount(IERC20Minimal(address(uint160(ids[i]))), values[i]);
            }
        }
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function setProtocolFeeController(IProtocolFeeController controller) external onlyOwner {
        protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(address(controller));
    }

    function setPoolProtocolFee(bytes32 id) external {
        uint8 newProtocolFee = fetchPoolProtocolFee(id);

        pools[id].setProtocolFee(newProtocolFee);
        emit PoolProtocolFeeUpdated(id, newProtocolFee);
    }

    function fetchPoolProtocolFee(bytes32 id) internal view returns (uint8 protocolFee) {
        if (address(protocolFeeController) != address(0)) {
            try protocolFeeController.protocolFeeForPool{gas: controllerGasLimit}(id) returns (
                uint8 updatedProtocolFee
            ) {
                protocolFee = updatedProtocolFee;
            } catch {}
        }
    }

    function collectProtocolFees(
        address recipient,
        IERC20Minimal token,
        uint256 amount
    ) external returns (uint256) {
        if (msg.sender != owner && msg.sender != address(protocolFeeController)) revert InvalidCaller();

        amount = (amount == 0) ? protocolFeesAccrued[token] : amount;
        protocolFeesAccrued[token] -= amount;
        TransferHelper.safeTransfer(token, recipient, amount);

        return amount;
    }
}
