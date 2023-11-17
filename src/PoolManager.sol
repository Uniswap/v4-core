// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Hooks} from "./libraries/Hooks.sol";
import {Pool} from "./libraries/Pool.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Position} from "./libraries/Position.sol";
import {FeeLibrary} from "./libraries/FeeLibrary.sol";
import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";
import {Owned} from "./Owned.sol";
import {IHooks} from "./interfaces/IHooks.sol";
import {IDynamicFeeManager} from "./interfaces/IDynamicFeeManager.sol";
import {IHookFeeManager} from "./interfaces/IHookFeeManager.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {ILockCallback} from "./interfaces/callback/ILockCallback.sol";
import {Fees} from "./Fees.sol";
import {Claims} from "./Claims.sol";
import {PoolId, PoolIdLibrary} from "./types/PoolId.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";
import {Lockers} from "./libraries/Lockers.sol";

/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, Fees, NoDelegateCall, Claims {
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;
    using Position for mapping(bytes32 => Position.Info);
    using CurrencyLibrary for Currency;
    using FeeLibrary for uint24;

    /// @inheritdoc IPoolManager
    int24 public constant MAX_TICK_SPACING = TickMath.MAX_TICK_SPACING;

    /// @inheritdoc IPoolManager
    int24 public constant MIN_TICK_SPACING = TickMath.MIN_TICK_SPACING;

    /// @dev Represents the currencies due/owed to each locker.
    /// Must all net to zero when the last lock is released.
    mapping(address locker => mapping(Currency currency => int256 currencyDelta)) public currencyDelta;

    /// @inheritdoc IPoolManager
    mapping(Currency currency => uint256) public override reservesOf;

    mapping(PoolId id => Pool.State) public pools;

    constructor(uint256 controllerGasLimit) Fees(controllerGasLimit) {}

    function _getPool(PoolKey memory key) private view returns (Pool.State storage) {
        return pools[key.toId()];
    }

    /// @inheritdoc IPoolManager
    function getSlot0(PoolId id)
        external
        view
        override
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFees, uint24 hookFees)
    {
        Pool.Slot0 memory slot0 = pools[id].slot0;

        return (slot0.sqrtPriceX96, slot0.tick, slot0.protocolFees, slot0.hookFees);
    }

    /// @inheritdoc IPoolManager
    function getLiquidity(PoolId id) external view override returns (uint128 liquidity) {
        return pools[id].liquidity;
    }

    /// @inheritdoc IPoolManager
    function getLiquidity(PoolId id, address _owner, int24 tickLower, int24 tickUpper)
        external
        view
        override
        returns (uint128 liquidity)
    {
        return pools[id].positions.get(_owner, tickLower, tickUpper).liquidity;
    }

    function getPosition(PoolId id, address owner, int24 tickLower, int24 tickUpper)
        external
        view
        override
        returns (Position.Info memory position)
    {
        return pools[id].positions.get(owner, tickLower, tickUpper);
    }

    /// @inheritdoc IPoolManager
    function getLock(uint256 i) external view override returns (address locker) {
        return Lockers.getLocker(i);
    }

    /// @inheritdoc IPoolManager
    function initialize(PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        override
        returns (int24 tick)
    {
        if (key.fee.isStaticFeeTooLarge()) revert FeeTooLarge();

        // see TickBitmap.sol for overflow conditions that can arise from tick spacing being too large
        if (key.tickSpacing > MAX_TICK_SPACING) revert TickSpacingTooLarge();
        if (key.tickSpacing < MIN_TICK_SPACING) revert TickSpacingTooSmall();
        if (key.currency0 >= key.currency1) revert CurrenciesInitializedOutOfOrder();
        if (!key.hooks.isValidHookAddress(key.fee)) revert Hooks.HookAddressNotValid(address(key.hooks));

        if (key.hooks.shouldCallBeforeInitialize()) {
            if (key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96, hookData) != IHooks.beforeInitialize.selector)
            {
                revert Hooks.InvalidHookResponse();
            }
        }

        PoolId id = key.toId();

        uint24 swapFee = key.fee.isDynamicFee() ? _fetchDynamicSwapFee(key) : key.fee.getStaticFee();

        tick = pools[id].initialize(sqrtPriceX96, _fetchProtocolFees(key), _fetchHookFees(key), swapFee);

        if (key.hooks.shouldCallAfterInitialize()) {
            if (
                key.hooks.afterInitialize(msg.sender, key, sqrtPriceX96, tick, hookData)
                    != IHooks.afterInitialize.selector
            ) {
                revert Hooks.InvalidHookResponse();
            }
        }

        // On intitalize we emit the key's fee, which tells us all fee settings a pool can have: either a static swap fee or dynamic swap fee and if the hook has enabled swap or withdraw fees.
        emit Initialize(id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
    }

    /// @inheritdoc IPoolManager
    function lock(bytes calldata data) external override returns (bytes memory result) {
        Lockers.push(msg.sender);

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = ILockCallback(msg.sender).lockAcquired(data);

        if (Lockers.length() == 1) {
            if (Lockers.nonzeroDeltaCount() != 0) revert CurrencyNotSettled();
            Lockers.clear();
        } else {
            Lockers.pop();
        }
    }

    function _accountDelta(Currency currency, int128 delta) internal {
        if (delta == 0) return;

        address locker = Lockers.getCurrentLocker();
        int256 current = currencyDelta[locker][currency];
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                Lockers.decrementNonzeroDeltaCount();
            } else if (current == 0) {
                Lockers.incrementNonzeroDeltaCount();
            }
        }

        currencyDelta[locker][currency] = next;
    }

    /// @dev Accumulates a balance change to a map of currency to balance changes
    function _accountPoolBalanceDelta(PoolKey memory key, BalanceDelta delta) internal {
        _accountDelta(key.currency0, delta.amount0());
        _accountDelta(key.currency1, delta.amount1());
    }

    modifier onlyByLocker() {
        address locker = Lockers.getCurrentLocker();
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    /// @inheritdoc IPoolManager
    function modifyPosition(
        PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params,
        bytes calldata hookData
    ) external override noDelegateCall onlyByLocker returns (BalanceDelta delta) {
        if (key.hooks.shouldCallBeforeModifyPosition()) {
            if (
                key.hooks.beforeModifyPosition(msg.sender, key, params, hookData)
                    != IHooks.beforeModifyPosition.selector
            ) {
                revert Hooks.InvalidHookResponse();
            }
        }

        PoolId id = key.toId();
        Pool.FeeAmounts memory feeAmounts;
        (delta, feeAmounts) = pools[id].modifyPosition(
            Pool.ModifyPositionParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.tickSpacing
            })
        );

        _accountPoolBalanceDelta(key, delta);

        unchecked {
            if (feeAmounts.feeForProtocol0 > 0) {
                protocolFeesAccrued[key.currency0] += feeAmounts.feeForProtocol0;
            }
            if (feeAmounts.feeForProtocol1 > 0) {
                protocolFeesAccrued[key.currency1] += feeAmounts.feeForProtocol1;
            }
            if (feeAmounts.feeForHook0 > 0) {
                hookFeesAccrued[address(key.hooks)][key.currency0] += feeAmounts.feeForHook0;
            }
            if (feeAmounts.feeForHook1 > 0) {
                hookFeesAccrued[address(key.hooks)][key.currency1] += feeAmounts.feeForHook1;
            }
        }

        if (key.hooks.shouldCallAfterModifyPosition()) {
            if (
                key.hooks.afterModifyPosition(msg.sender, key, params, delta, hookData)
                    != IHooks.afterModifyPosition.selector
            ) {
                revert Hooks.InvalidHookResponse();
            }
        }

        emit ModifyPosition(id, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta);
    }

    /// @inheritdoc IPoolManager
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params, bytes calldata hookData)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta delta)
    {
        if (key.hooks.shouldCallBeforeSwap()) {
            if (key.hooks.beforeSwap(msg.sender, key, params, hookData) != IHooks.beforeSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        PoolId id = key.toId();

        uint256 feeForProtocol;
        uint256 feeForHook;
        uint24 swapFee;
        Pool.SwapState memory state;
        (delta, feeForProtocol, feeForHook, swapFee, state) = pools[id].swap(
            Pool.SwapParams({
                tickSpacing: key.tickSpacing,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        _accountPoolBalanceDelta(key, delta);
        // the fee is on the input currency

        unchecked {
            if (feeForProtocol > 0) {
                protocolFeesAccrued[params.zeroForOne ? key.currency0 : key.currency1] += feeForProtocol;
            }
            if (feeForHook > 0) {
                hookFeesAccrued[address(key.hooks)][params.zeroForOne ? key.currency0 : key.currency1] += feeForHook;
            }
        }

        if (key.hooks.shouldCallAfterSwap()) {
            if (key.hooks.afterSwap(msg.sender, key, params, delta, hookData) != IHooks.afterSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        emit Swap(
            id, msg.sender, delta.amount0(), delta.amount1(), state.sqrtPriceX96, state.liquidity, state.tick, swapFee
        );
    }

    /// @inheritdoc IPoolManager
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta delta)
    {
        if (key.hooks.shouldCallBeforeDonate()) {
            if (key.hooks.beforeDonate(msg.sender, key, amount0, amount1, hookData) != IHooks.beforeDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        delta = _getPool(key).donate(amount0, amount1);

        _accountPoolBalanceDelta(key, delta);

        if (key.hooks.shouldCallAfterDonate()) {
            if (key.hooks.afterDonate(msg.sender, key, amount0, amount1, hookData) != IHooks.afterDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc IPoolManager
    function take(Currency currency, address to, uint256 amount) external override noDelegateCall onlyByLocker {
        _accountDelta(currency, amount.toInt128());
        reservesOf[currency] -= amount;
        currency.transfer(to, amount);
    }

    /// @inheritdoc IPoolManager
    function settle(Currency currency) external payable override noDelegateCall onlyByLocker returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[currency];
        reservesOf[currency] = currency.balanceOfSelf();
        paid = reservesOf[currency] - reservesBefore;
        // subtraction must be safe
        _accountDelta(currency, -(paid.toInt128()));
    }

    /// @inheritdoc IPoolManager
    function mint(Currency currency, address to, uint256 amount) external noDelegateCall onlyByLocker {
        _accountDelta(currency, amount.toInt128());
        _mint(to, currency, amount);
    }

    /// @inheritdoc IPoolManager
    function burn(Currency currency, uint256 amount) external noDelegateCall onlyByLocker {
        _accountDelta(currency, -(amount.toInt128()));
        _burn(currency, amount);
    }

    function setProtocolFees(PoolKey memory key) external {
        uint24 newProtocolFees = _fetchProtocolFees(key);
        PoolId id = key.toId();
        pools[id].setProtocolFees(newProtocolFees);
        emit ProtocolFeeUpdated(id, newProtocolFees);
    }

    function setHookFees(PoolKey memory key) external {
        uint24 newHookFees = _fetchHookFees(key);
        PoolId id = key.toId();
        pools[id].setHookFees(newHookFees);
        emit HookFeeUpdated(id, newHookFees);
    }

    function updateDynamicSwapFee(PoolKey memory key) external {
        if (key.fee.isDynamicFee()) {
            uint24 newDynamicSwapFee = _fetchDynamicSwapFee(key);
            PoolId id = key.toId();
            pools[id].setSwapFee(newDynamicSwapFee);
            emit DynamicSwapFeeUpdated(id, newDynamicSwapFee);
        } else {
            revert FeeNotDynamic();
        }
    }

    function extsload(bytes32 slot) external view returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes memory) {
        bytes memory value = new bytes(32 * nSlots);

        /// @solidity memory-safe-assembly
        assembly {
            for { let i := 0 } lt(i, nSlots) { i := add(i, 1) } {
                mstore(add(value, mul(add(i, 1), 32)), sload(add(startSlot, i)))
            }
        }

        return value;
    }

    function getLockLength() external view returns (uint256 _length) {
        return Lockers.length();
    }

    function getLockNonzeroDeltaCount() external view returns (uint256 _nonzeroDeltaCount) {
        return Lockers.nonzeroDeltaCount();
    }

    /// @notice receive native tokens for native pools
    receive() external payable {}
}
