// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Hooks} from "../libraries/Hooks.sol";
import {Pool} from "../libraries/Pool.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {Position} from "../libraries/Position.sol";
import {LPFeeLibrary} from "../libraries/LPFeeLibrary.sol";
import {Currency} from "../types/Currency.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {NoDelegateCall} from "../NoDelegateCall.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/callback/IUnlockCallback.sol";
import {ProtocolFees} from "../ProtocolFees.sol";
import {ERC6909Claims} from "../ERC6909Claims.sol";
import {PoolId} from "../types/PoolId.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {Lock} from "../libraries/Lock.sol";
import {CurrencyDelta} from "../libraries/CurrencyDelta.sol";
import {NonzeroDeltaCount} from "../libraries/NonzeroDeltaCount.sol";
import {CurrencyReserves} from "../libraries/CurrencyReserves.sol";
import {Extsload} from "../Extsload.sol";
import {Exttload} from "../Exttload.sol";
import {CustomRevert} from "../libraries/CustomRevert.sol";

/// @notice A proxy pool manager that delegates calls to the real/delegate pool manager
contract ProxyPoolManager is IPoolManager, ProtocolFees, NoDelegateCall, ERC6909Claims, Extsload, Exttload {
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;
    using Position for mapping(bytes32 => Position.State);
    using CurrencyDelta for Currency;
    using LPFeeLibrary for uint24;
    using CurrencyReserves for Currency;
    using CustomRevert for bytes4;

    int24 private constant MAX_TICK_SPACING = TickMath.MAX_TICK_SPACING;

    int24 private constant MIN_TICK_SPACING = TickMath.MIN_TICK_SPACING;

    mapping(PoolId id => Pool.State) internal _pools;

    address internal immutable _delegateManager;

    constructor(address delegateManager) ProtocolFees(msg.sender) {
        _delegateManager = delegateManager;
    }

    /// @notice This will revert if the contract is locked
    modifier onlyWhenUnlocked() {
        if (!Lock.isUnlocked()) ManagerLocked.selector.revertWith();
        _;
    }

    /// @inheritdoc IPoolManager
    function unlock(bytes calldata data) external noDelegateCall returns (bytes memory result) {
        if (Lock.isUnlocked()) AlreadyUnlocked.selector.revertWith();

        Lock.unlock();

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = IUnlockCallback(msg.sender).unlockCallback(data);

        if (NonzeroDeltaCount.read() != 0) CurrencyNotSettled.selector.revertWith();
        Lock.lock();
    }

    /// @inheritdoc IPoolManager
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external noDelegateCall returns (int24 tick) {
        // see TickBitmap.sol for overflow conditions that can arise from tick spacing being too large
        if (key.tickSpacing > MAX_TICK_SPACING) TickSpacingTooLarge.selector.revertWith(key.tickSpacing);
        if (key.tickSpacing < MIN_TICK_SPACING) TickSpacingTooSmall.selector.revertWith(key.tickSpacing);
        if (key.currency0 >= key.currency1) {
            CurrenciesOutOfOrderOrEqual.selector.revertWith(
                Currency.unwrap(key.currency0), Currency.unwrap(key.currency1)
            );
        }
        if (!key.hooks.isValidHookAddress(key.fee)) Hooks.HookAddressNotValid.selector.revertWith(address(key.hooks));

        uint24 lpFee = key.fee.getInitialLPFee();

        key.hooks.beforeInitialize(key, sqrtPriceX96);

        PoolId id = key.toId();

        tick = _pools[id].initialize(sqrtPriceX96, lpFee);

        key.hooks.afterInitialize(key, sqrtPriceX96, tick);

        // emit all details of a pool key. poolkeys are not saved in storage and must always be provided by the caller
        // the key's fee may be a static fee or a sentinel to denote a dynamic fee.
        emit Initialize(id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks, sqrtPriceX96, tick);
    }

    /// @inheritdoc IPoolManager
    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external onlyWhenUnlocked noDelegateCall returns (BalanceDelta callerDelta, BalanceDelta feesAccrued) {
        bytes memory result = _delegateCall(
            _delegateManager, abi.encodeWithSelector(this.modifyLiquidity.selector, key, params, hookData)
        );

        return abi.decode(result, (BalanceDelta, BalanceDelta));
    }

    /// @inheritdoc IPoolManager
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params, bytes calldata hookData)
        external
        onlyWhenUnlocked
        noDelegateCall
        returns (BalanceDelta swapDelta)
    {
        bytes memory result =
            _delegateCall(_delegateManager, abi.encodeWithSelector(this.swap.selector, key, params, hookData));

        return abi.decode(result, (BalanceDelta));
    }

    /// @inheritdoc IPoolManager
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        onlyWhenUnlocked
        noDelegateCall
        returns (BalanceDelta delta)
    {
        bytes memory result = _delegateCall(
            _delegateManager, abi.encodeWithSelector(this.donate.selector, key, amount0, amount1, hookData)
        );

        return abi.decode(result, (BalanceDelta));
    }

    /// @inheritdoc IPoolManager
    function sync(Currency currency) public {
        // address(0) is used for the native currency
        if (currency.isAddressZero()) {
            // The reserves balance is not used for native settling, so we only need to reset the currency.
            CurrencyReserves.resetCurrency();
        } else {
            uint256 balance = currency.balanceOfSelf();
            CurrencyReserves.syncCurrencyAndReserves(currency, balance);
        }
    }

    /// @inheritdoc IPoolManager
    function take(Currency currency, address to, uint256 amount) external onlyWhenUnlocked noDelegateCall {
        _delegateCall(_delegateManager, abi.encodeWithSelector(this.take.selector, currency, to, amount));
    }

    /// @inheritdoc IPoolManager
    function settle() external payable onlyWhenUnlocked noDelegateCall returns (uint256 paid) {
        bytes memory result = _delegateCall(_delegateManager, abi.encodeWithSelector(this.settle.selector));

        return abi.decode(result, (uint256));
    }

    /// @inheritdoc IPoolManager
    function settleFor(address recipient) external payable onlyWhenUnlocked noDelegateCall returns (uint256 paid) {
        bytes memory result =
            _delegateCall(_delegateManager, abi.encodeWithSelector(this.settleFor.selector, recipient));

        return abi.decode(result, (uint256));
    }

    /// @inheritdoc IPoolManager
    function clear(Currency currency, uint256 amount) external onlyWhenUnlocked {
        _delegateCall(_delegateManager, abi.encodeWithSelector(this.clear.selector, currency, amount));
    }

    /// @inheritdoc IPoolManager
    function mint(address to, uint256 id, uint256 amount) external onlyWhenUnlocked noDelegateCall {
        _delegateCall(_delegateManager, abi.encodeWithSelector(this.mint.selector, to, id, amount));
    }

    /// @inheritdoc IPoolManager
    function burn(address from, uint256 id, uint256 amount) external onlyWhenUnlocked noDelegateCall {
        _delegateCall(_delegateManager, abi.encodeWithSelector(this.burn.selector, from, id, amount));
    }

    /// @inheritdoc IPoolManager
    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external {
        if (!key.fee.isDynamicFee() || msg.sender != address(key.hooks)) {
            UnauthorizedDynamicLPFeeUpdate.selector.revertWith();
        }
        newDynamicLPFee.validate();
        PoolId id = key.toId();
        _pools[id].setLPFee(newDynamicLPFee);
    }

    /// @notice Make a delegate call, bubble up any error or return the result
    function _delegateCall(address target, bytes memory data) internal returns (bytes memory result) {
        (bool success, bytes memory returnData) = target.delegatecall(data);

        if (!success) {
            if (returnData.length == 0) {
                revert();
            } else {
                assembly {
                    let size := mload(returnData)
                    revert(add(32, returnData), size)
                }
            }
        }

        return returnData;
    }

    /// @notice Implementation of the _getPool function defined in ProtocolFees
    function _getPool(PoolId id) internal view override returns (Pool.State storage) {
        return _pools[id];
    }

    /// @notice Implementation of the _isUnlocked function defined in ProtocolFees
    function _isUnlocked() internal view override returns (bool) {
        return Lock.isUnlocked();
    }
}
