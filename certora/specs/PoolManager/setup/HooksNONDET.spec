methods {
    // NONDET summary for IHooks
    function _.beforeInitialize(address, PoolManager.PoolKey, uint160)
        external => NONDET;
    function _.afterInitialize(address, PoolManager.PoolKey, uint160, int24)
        external => NONDET;
    function _.beforeAddLiquidity(
        address,
        PoolManager.PoolKey,
        IPoolManager.ModifyLiquidityParams,
        bytes hookData
    ) external => NONDET;
    function _.afterAddLiquidity(
        address,
        PoolManager.PoolKey,
        IPoolManager.ModifyLiquidityParams,
        PoolManager.BalanceDelta,
        PoolManager.BalanceDelta,
        bytes hookData
    ) external => NONDET;
     function _.beforeRemoveLiquidity(
        address,
        PoolManager.PoolKey,
        IPoolManager.ModifyLiquidityParams,
        bytes hookData
    ) external => NONDET;
    function _.afterRemoveLiquidity(
        address,
        PoolManager.PoolKey,
        IPoolManager.ModifyLiquidityParams,
        PoolManager.BalanceDelta,
        PoolManager.BalanceDelta,
        bytes hookData
    ) external => NONDET;
    function _.beforeSwap(address, PoolManager.PoolKey, IPoolManager.SwapParams, bytes hookData) external => NONDET;
    function _.afterSwap(
        address,
        PoolManager.PoolKey,
        IPoolManager.SwapParams,
        PoolManager.BalanceDelta,
        bytes hookData
    ) external => NONDET;
    function _.beforeDonate(address, PoolManager.PoolKey, uint256, uint256, bytes hookData)
        external => NONDET;
    function _.afterDonate(address, PoolManager.PoolKey, uint256, uint256, bytes hookData)
        external => NONDET;
    
    /// Pure function is summarized by a generic arbitratry mapping - this is logically sound.
    function Hooks.hasPermission(address self, uint160 flag) internal returns (bool) => CVLHasPermission(self, flag);
}

persistent ghost CVLHasPermission(address, uint160) returns bool;

definition MIN_INT128() returns int128 = -(1 << 127);
definition BEFORE_SWAP_FLAG() returns uint160 = 1 << 7;
definition AFTER_SWAP_FLAG() returns uint160 = 1 << 6;
definition BEFORE_SWAP_RETURNS_DELTA_FLAG() returns uint160 = 1 << 3;
definition AFTER_SWAP_RETURNS_DELTA_FLAG() returns uint160 = 1 << 2;
definition BEFORE_ADD_LIQUIDITY_FLAG() returns uint160 = 1 << 11;
definition AFTER_ADD_LIQUIDITY_FLAG() returns uint160 = 1 << 10;
definition BEFORE_REMOVE_LIQUIDITY_FLAG() returns uint160 = 1 << 9;
definition AFTER_REMOVE_LIQUIDITY_FLAG() returns uint160 =  1 << 8;

function randomHook(address self, bytes data) returns bytes {
    bytes ret;
    return ret;
}
