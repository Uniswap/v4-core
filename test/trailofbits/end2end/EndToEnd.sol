// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IHooks} from "src/interfaces/IHooks.sol";
import {Hooks} from "src/libraries/Hooks.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";

import {CurrencyLibrary, Currency} from "src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {BalanceDelta} from "src/types/BalanceDelta.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "src/libraries/LPFeeLibrary.sol";
import {TickMath} from "src/libraries/TickMath.sol";

import {PoolTestBase} from "src/test/PoolTestBase.sol";
import {PoolModifyLiquidityTest} from "src/test/PoolModifyLiquidityTest.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {CurrencySettler} from "test/utils/CurrencySettler.sol";

import {IActor} from "./IActor.sol";
import {PropertiesAsserts} from "../PropertiesHelper.sol";
import {SwapInfo, SwapInfoLibrary} from "./Lib.sol";

import {SwapActor} from "./SwapActor.sol";
import {LiquidityActor} from "./LiquidityActor.sol";
import {DonationActor} from "./DonationActor.sol";


contract EndToEnd is PropertiesAsserts, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    PoolKey[] DeployedPools;
    mapping(PoolId => bool) PoolInitialized;
    Currency[] Currencies;


    // actors
    LiquidityActor[] LiquidityActors;
    DonationActor[] DonationActors;
    SwapActor[] SwapActors;


    uint NUMBER_CURRENCIES = 2;
    uint NUMBER_LIQUIDITY_ACTORS = 1;
    uint NUMBER_DONATION_ACTORS = 1;
    uint NUMBER_SWAP_ACTORS = 1;

    constructor () payable {
        Deployers.deployFreshManagerAndRouters();

        // Initialize currencies
        for (uint i = 0; i < NUMBER_CURRENCIES; i++) {
            Currencies.push(deployMintAndApproveCurrency());
        }

        for (uint i = 0; i < NUMBER_LIQUIDITY_ACTORS; i++) {
            LiquidityActor a = new LiquidityActor(manager);
            LiquidityActors.push(a);
            _setupActorApprovals(a);
        }

        for (uint i = 0; i < NUMBER_DONATION_ACTORS; i++) {
            DonationActor a = new DonationActor(manager);
            DonationActors.push(a);
            _setupActorApprovals(a);
        }

        for (uint i = 0; i < NUMBER_SWAP_ACTORS; i++) {
            SwapActor a = new SwapActor(manager);
            SwapActors.push(a);
            _setupActorApprovals(a);
        }
    }

    function _setupActorApprovals(IActor c) internal {
        address[9] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor()),
            address(actionsRouter)
        ];

        for(uint i = 0; i < NUMBER_CURRENCIES; i++) {
            Currency cur = Currencies[i];
            // By giving actors approval to this contracts funds, we allow them to search the full totalSupply space.
            // If we distributed tokens to each actor, they would be limited to exploration using tokens up to 
            // totalSupply/numActors.
            MockERC20(Currency.unwrap(cur)).approve(address(c), type(uint256).max);

            for( uint approveI=0; approveI< toApprove.length; approveI++) {
                c.proxyApprove(cur, toApprove[approveI]);
            }
        }
    }

    function _clampLiquidityActor(uint8 actorIndex) internal returns (LiquidityActor) {
        actorIndex = uint8(clampBetween(actorIndex, 0, NUMBER_LIQUIDITY_ACTORS-1));
        emit LogUint256("LiquidityActor index", actorIndex);
        return LiquidityActors[actorIndex];
    }

    function _clampDonationActor(uint8 actorIndex) internal returns (DonationActor) {
        actorIndex = uint8(clampBetween(actorIndex, 0, NUMBER_DONATION_ACTORS-1));
        emit LogUint256("DonationActor index", actorIndex);
        return DonationActors[actorIndex];
    }
    function _clampSwapActor(uint8 actorIndex) internal returns (SwapActor) {
        actorIndex = uint8(clampBetween(actorIndex, 0, NUMBER_SWAP_ACTORS-1));
        emit LogUint256("SwapActor index", actorIndex);
        return SwapActors[actorIndex];
    }

    function _clampToValidCurrencies(uint8 currency1I, uint8 currency2I) internal returns (Currency, Currency) {
        uint c1 = clampBetween(currency1I, 0, NUMBER_CURRENCIES-1);
        uint c2 = clampBetween(currency2I, 0, NUMBER_CURRENCIES-1);
        require(c1 != c2);

        Currency cur1 = Currencies[c1];
        Currency cur2 = Currencies[c2];
        if (cur1 >= cur2) {
            emit LogAddress("address 1", address(Currency.unwrap(cur2)));
            emit LogAddress("address 2", address(Currency.unwrap(cur1)));
            return (cur2, cur1);
        } else {
            emit LogAddress("address 1", address(Currency.unwrap(cur1)));
            emit LogAddress("address 2", address(Currency.unwrap(cur2)));
            return (cur1, cur2);
        }
    }

    function _clampToValidPool(uint poolIndex) internal returns ( PoolKey memory) {
        poolIndex = clampBetween(poolIndex, 0, DeployedPools.length-1);
        emit LogUint256("Pool index", poolIndex);
        return DeployedPools[poolIndex];
    }

    function _clampToUsableTicks(int24 minTick, int24 maxTick, PoolKey memory poolKey) internal returns (int24, int24) {
        int24 minUsableTick = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 maxUsableTick = TickMath.maxUsableTick(poolKey.tickSpacing);

        emit LogInt256("minUsableTick", minUsableTick);
        emit LogInt256("maxUsableTick", maxUsableTick);

        minTick = int24(clampBetween(minTick, minUsableTick, maxUsableTick));
        maxTick = int24(clampBetween(maxTick, minUsableTick, maxUsableTick));

        if (maxTick < minTick) {
            int24 tmp = minTick;
            minTick = maxTick;
            maxTick = tmp;
        }

        emit LogInt256("minTick", minTick);
        emit LogInt256("maxTick", maxTick);
        return (minTick, maxTick);
    }

    /// @custom:notes This works the same way as e2e_createPool, but clamps inputs to correct values to help our coverage.
    function e2e_CreatePool_Coverage(uint8 currency1I, uint8 currency2I, int16 tickSpacing, uint256 startPrice, uint256 fee) public {
        Currency c1;
        Currency c2;
        (c1, c2) =  _clampToValidCurrencies(currency1I, currency2I);
        int24 tickSpacingClamped = int24(clampBetween(tickSpacing,1, type(int16).max));
        emit LogInt256("tickSpacingClamped", tickSpacingClamped);

        uint256 initialPrice = clampBetween(startPrice, 4295128739, 1461446703485210103287273052203988822378723970342-1);
        emit LogUint256("initialPrice", initialPrice);
        
        uint256 initialFee = clampBetween(fee, 0, 1_000_000);
        emit LogUint256("initialFee", fee);

        PoolKey memory k = PoolKey(c1, c2, uint24(initialFee), tickSpacingClamped, IHooks(address(0)));
        PoolId id = k.toId();
        if (PoolInitialized[id]){
            return;
        }

        int24 tick;
        try manager.initialize(k, uint160(initialPrice), ZERO_BYTES) returns (int24 t) {
            tick = t;
        }            
        catch  {
            // todo: REVISIT
            // assertWithMsg(false, "manager.initialize() threw an unknown exception. investigate");

            return;
        }
        
        DeployedPools.push(k);
        PoolInitialized[id] = true;

        e2e_ProvideLiquidityFullRange(0, 0, 1 ether);
    }


    /// @custom:notes This function facilitates the creation of new pools for other properties.
    function e2e_CreatePool(uint8 currency1I, uint8 currency2I, int16 tickSpacing, uint256 startPrice, uint256 fee) public {
        Currency c1;
        Currency c2;
        (c1, c2) =  _clampToValidCurrencies(currency1I, currency2I);
        int24 tickSpacingClamped = int24(clampBetween(tickSpacing,1, type(int16).max));
        emit LogInt256("tickSpacingClamped", tickSpacingClamped);

        uint256 initialPrice = startPrice;
        emit LogUint256("initialPrice", initialPrice);
        emit LogUint256("initialFee", fee);

        PoolKey memory k = PoolKey(c1, c2, uint24(fee), tickSpacingClamped, IHooks(address(0)));
        PoolId id = k.toId();
        bool poolinitialized = PoolInitialized[id];

        int24 tick;
        try manager.initialize(k, uint160(initialPrice), ZERO_BYTES) returns (int24 t) {
            tick = t;
        }            
        catch (bytes memory data) {
            if (bytes4(data) == bytes4(keccak256(bytes("PoolAlreadyInitialized()")) )){
                // allowable exception iff poolInitialized
                assertWithMsg(poolinitialized, "initialize() reverted with PoolAlreadyInitialized() but pool is not initialized");
                return;
            }
            if (bytes4(data) == bytes4(keccak256(bytes("InvalidSqrtPrice(uint160)")) )){
                // allowable exception iff initialPrice is outside the valid range
                assertWithMsg(initialPrice < 4295128739 || initialPrice > 1461446703485210103287273052203988822378723970342-1, "initialize() reverted with InvalidSqrtPrice() but initialPrice is within valid range");
                return;
            }
            if (bytes4(data) == bytes4(keccak256(bytes("LPFeeTooLarge(uint24)")) )){
                // allowable exception iff fee is larger than 1_000_000
                assertGt(fee, 1_000_000, "initialize() reverted with LPFeeTooLarge() but initialFee is within valid range");
                return;
            }
            // assertWithMsg(false, "manager.initialize() threw an unknown exception. investigate");
            return;
        }
        // we should have reverted if pool was initialized
        assertWithMsg(!poolinitialized, "initialize() did not revert, but pool is not initialized");

        // verify tick is valid
        emit LogInt256("tick", tick);
        assertGte(tick, TickMath.MIN_TICK, "tick below valid range");
        assertLte(tick, TickMath.MAX_TICK, "tick above valid range");

        // todo: alternate property about tick width?
        
        DeployedPools.push(k);
        PoolInitialized[id] = true;

        e2e_ProvideLiquidityFullRange(0, 0, 1 ether);
    }

    function e2e_DonateToLiquidity(uint8 actorIndex, uint poolIndex, uint256 amount0, uint256 amount1) public {
        DonationActor actor = _clampDonationActor(actorIndex);
        PoolKey memory poolKey = _clampToValidPool(poolIndex);
        actor.Donate(poolKey, amount0, amount1);
    }


    function e2e_ProvideLiquidity(uint8 actorIndex, uint poolIndex, int24 minTick, int24 maxTick, int256 liquidityDelta) public {
        LiquidityActor actor = _clampLiquidityActor(actorIndex);
        PoolKey memory poolKey = _clampToValidPool(poolIndex);

        (minTick, maxTick) = _clampToUsableTicks(minTick, maxTick, poolKey);
        actor.ProvideLiquidity(poolKey, minTick, maxTick, liquidityDelta);
    }

    /// @custom:property delta0 and delta1 must be greater than zero when providing LP for full-range liquidity
    /// @custom:precondition Pools Created (e2e_CreatePool)
    function e2e_ProvideLiquidityFullRange(uint8 actorIndex, uint poolIndex, int256 liquidityDelta) public {
        LiquidityActor actor = _clampLiquidityActor(actorIndex);
        PoolKey memory poolKey = _clampToValidPool(poolIndex);
        int24 minTick = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 maxTick = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint256 delta0;
        uint256 delta1;
        (delta0, delta1) = actor.ProvideLiquidity(poolKey, minTick, maxTick, liquidityDelta);

    }

    function e2e_SwapOneDirection(uint8 actorIndex, uint poolIndex, int256 amountSpecified, bool zeroForOne) public {
        SwapActor actor = _clampSwapActor(actorIndex);
        PoolKey memory poolKey = _clampToValidPool(poolIndex);

        actor.swapOneDirection(zeroForOne, amountSpecified, poolKey);
    }

    function e2e_SwapBidirectional(uint8 actorIndex, uint poolIndex, int256 amountSpecified, bool zeroForOne)  public {
        SwapActor actor = _clampSwapActor(actorIndex);
        PoolKey memory poolKey = _clampToValidPool(poolIndex);

        actor.swapBiDirectional(zeroForOne, amountSpecified, poolKey);
    }
}