// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Hooks} from './libraries/Hooks.sol';
import {Pool} from './libraries/Pool.sol';
import {SafeCast} from './libraries/SafeCast.sol';
import {Position} from './libraries/Position.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';

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
    using CurrencyLibrary for Currency;

    /// @inheritdoc IPoolManager
    int24 public constant override MAX_TICK_SPACING = type(int16).max;

    /// @inheritdoc IPoolManager
    int24 public constant override MIN_TICK_SPACING = 1;

    mapping(bytes32 => Pool.State) public pools;

    mapping(Currency => uint256) public override protocolFeesAccrued;
    IProtocolFeeController public protocolFeeController;

    uint256 private immutable controllerGasLimit;

    constructor(uint256 _controllerGasLimit) ERC1155('') {
        controllerGasLimit = _controllerGasLimit;
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
        tick = pools[id].initialize(sqrtPriceX96, fetchPoolProtocolFee(key));

        if (key.hooks.shouldCallAfterInitialize()) {
            if (key.hooks.afterInitialize(msg.sender, key, sqrtPriceX96, tick) != IHooks.afterInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        emit Initialize(id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
    }

    /// @inheritdoc IPoolManager
    mapping(Currency => uint256) public override reservesOf;

    /// @inheritdoc IPoolManager
    function lockedBy(uint256 index) public view returns (address locker) {
        assembly {
            locker := tload(add(index, 1))
        }
    }

    /// @inheritdoc IPoolManager
    function lockedByLength() public view returns (uint256 length) {
        assembly {
            length := tload(0)
        }
    }

    /// @dev Push the latest locked by address from the stack
    /// @return index The index of the locker, i.e. the locker's unique identifier
    function pushLockedBy(address addr) internal returns (uint256 index) {
        assembly {
            index := tload(0)
            tstore(0, add(index, 1))
            tstore(add(index, 1), addr)
        }
    }

    /// @dev Pop the latest locked by address from the stack
    function popLockedBy() internal {
        assembly {
            let index := sub(tload(0), 1)
            tstore(0, index)
            tstore(index, 0)
        }
    }

    /// @inheritdoc IPoolManager
    function getNonzeroDeltaCount(uint256 id) public view returns (uint256 count) {
        assembly {
            count := tload(shl(128, id))
        }
    }

    function setNonzeroDeltaCount(uint256 id, uint256 count) internal {
        assembly {
            tstore(shl(128, id), count)
        }
    }

    /// @inheritdoc IPoolManager
    function getCurrencyDelta(uint256 id, Currency currency) public view returns (int256 delta) {
        uint256 key = uint256(keccak256(abi.encode(id, currency)));
        assembly {
            delta := tload(key)
        }
    }

    function setCurrencyDelta(
        uint256 id,
        Currency currency,
        int256 delta
    ) internal {
        uint256 key = uint256(keccak256(abi.encode(id, currency)));
        assembly {
            tstore(key, delta)
        }
    }

    /// @inheritdoc IPoolManager
    function lock(bytes calldata data) external override returns (bytes memory result) {
        uint256 id = pushLockedBy(msg.sender);

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = ILockCallback(msg.sender).lockAcquired(data);

        unchecked {
            if (getNonzeroDeltaCount(id) != 0) revert CurrencyNotSettled();
        }

        popLockedBy();
    }

    function _accountDelta(
        uint256 id,
        Currency currency,
        int256 delta
    ) internal {
        if (delta == 0) return;

        int256 current = getCurrencyDelta(id, currency);

        int256 next = current + delta;
        unchecked {
            if (next == 0) {
                setNonzeroDeltaCount(id, getNonzeroDeltaCount(id) - 1);
            } else if (current == 0) {
                setNonzeroDeltaCount(id, getNonzeroDeltaCount(id) + 1);
            }
        }

        setCurrencyDelta(id, currency, next);
    }

    function lockerIdCurrent() internal view returns (uint256) {
        unchecked {
            return lockedByLength() - 1;
        }
    }

    /// @dev Accumulates a balance change to a map of currency to balance changes
    function _accountPoolBalanceDelta(PoolKey memory key, IPoolManager.BalanceDelta memory delta) internal {
        unchecked {
            uint256 id = lockerIdCurrent();
            _accountDelta(id, key.currency0, delta.amount0);
            _accountDelta(id, key.currency1, delta.amount1);
        }
    }

    modifier onlyByLocker() {
        address lb = lockedBy(lockedByLength() - 1);
        if (msg.sender != lb) revert LockedBy(lb);
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

        bytes32 poolId = key.toId();
        delta = pools[poolId].modifyPosition(
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

        emit ModifyPosition(poolId, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta);
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
        Pool.SwapState memory state;
        bytes32 poolId = key.toId();
        (delta, feeForProtocol, state) = pools[poolId].swap(
            Pool.SwapParams({
                fee: key.fee,
                tickSpacing: key.tickSpacing,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        _accountPoolBalanceDelta(key, delta);
        // the fee is on the input currency

        unchecked {
            if (feeForProtocol > 0)
                protocolFeesAccrued[params.zeroForOne ? key.currency0 : key.currency1] += feeForProtocol;
        }

        if (key.hooks.shouldCallAfterSwap()) {
            if (key.hooks.afterSwap(msg.sender, key, params, delta) != IHooks.afterSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        emit Swap(poolId, msg.sender, delta.amount0, delta.amount1, state.sqrtPriceX96, state.liquidity, state.tick);
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
        Currency currency,
        address to,
        uint256 amount
    ) external override noDelegateCall onlyByLocker {
        _accountDelta(lockerIdCurrent(), currency, amount.toInt256());
        reservesOf[currency] -= amount;
        currency.transfer(to, amount);
    }

    /// @inheritdoc IPoolManager
    function mint(
        Currency currency,
        address to,
        uint256 amount
    ) external override noDelegateCall onlyByLocker {
        _accountDelta(lockerIdCurrent(), currency, amount.toInt256());
        _mint(to, currency.toId(), amount, '');
    }

    /// @inheritdoc IPoolManager
    function settle(Currency currency) external payable override noDelegateCall onlyByLocker returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[currency];
        reservesOf[currency] = currency.balanceOfSelf();
        paid = reservesOf[currency] - reservesBefore;
        // subtraction must be safe
        _accountDelta(lockerIdCurrent(), currency, -(paid.toInt256()));
    }

    function _burnAndAccount(Currency currency, uint256 amount) internal {
        _burn(address(this), currency.toId(), amount);
        _accountDelta(lockerIdCurrent(), currency, -(amount.toInt256()));
    }

    function onERC1155Received(
        address,
        address,
        uint256 id,
        uint256 value,
        bytes calldata
    ) external returns (bytes4) {
        if (msg.sender != address(this)) revert NotPoolManagerToken();
        _burnAndAccount(CurrencyLibrary.fromId(id), value);
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
                _burnAndAccount(CurrencyLibrary.fromId(ids[i]), values[i]);
            }
        }
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function setProtocolFeeController(IProtocolFeeController controller) external onlyOwner {
        protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(address(controller));
    }

    function setPoolProtocolFee(PoolKey memory key) external {
        uint8 newProtocolFee = fetchPoolProtocolFee(key);

        _getPool(key).setProtocolFee(newProtocolFee);
        emit ProtocolFeeUpdated(key.toId(), newProtocolFee);
    }

    function fetchPoolProtocolFee(PoolKey memory key) internal view returns (uint8 protocolFee) {
        if (address(protocolFeeController) != address(0)) {
            // note that EIP-150 mandates that calls requesting more than 63/64ths of remaining gas
            // will be allotted no more than this amount, so controllerGasLimit must be set with this
            // in mind.
            if (gasleft() < controllerGasLimit) revert ProtocolFeeCannotBeFetched();
            try protocolFeeController.protocolFeeForPool{gas: controllerGasLimit}(key) returns (
                uint8 updatedProtocolFee
            ) {
                protocolFee = updatedProtocolFee;
            } catch {}
        }
    }

    function collectProtocolFees(
        address recipient,
        Currency currency,
        uint256 amount
    ) external returns (uint256) {
        if (msg.sender != owner && msg.sender != address(protocolFeeController)) revert InvalidCaller();

        amount = (amount == 0) ? protocolFeesAccrued[currency] : amount;
        protocolFeesAccrued[currency] -= amount;
        currency.transfer(recipient, amount);

        return amount;
    }

    /// @notice receive native tokens for native pools
    receive() external payable {}
}
