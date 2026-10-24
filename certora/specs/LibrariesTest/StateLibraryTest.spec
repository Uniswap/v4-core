using StateLibraryTest as test;
using PoolStateGetters as PoolManager;

methods {
    /// State library
    function test.getSlot0(StateLibraryTest.PoolId) external returns (uint160,int24,uint24,uint24) envfree;
    function test.getTickInfo(StateLibraryTest.PoolId, int24) external returns (uint128,int128,uint256,uint256) envfree;
    function test.getTickLiquidity(StateLibraryTest.PoolId, int24) external returns (uint128,int128) envfree;
    function test.getFeeGrowthGlobals(StateLibraryTest.PoolId) external returns (uint256,uint256) envfree;
    function test.getTickFeeGrowthOutside(StateLibraryTest.PoolId, int24) external returns (uint256,uint256) envfree;
    function test.getLiquidity(StateLibraryTest.PoolId) external returns (uint128) envfree;
    function test.getPositionInfo(StateLibraryTest.PoolId, bytes32) external returns (uint128,uint256,uint256) envfree;
    function test.getTickBitmap(StateLibraryTest.PoolId, int16) external returns (uint256) envfree;
    function test.getPositionLiquidity(StateLibraryTest.PoolId, bytes32) external returns (uint128) envfree;

    function test.getSqrtPriceX96(StateLibraryTest.Slot0) external returns (uint160) envfree;
    function test.getTick(StateLibraryTest.Slot0) external returns (int24) envfree;
    function test.getProtocolFee(StateLibraryTest.Slot0) external returns (uint24) envfree;
    function test.getLpFee(StateLibraryTest.Slot0) external returns (uint24) envfree;

    /// PoolStateGetters

    /// Slot0
    function PoolManager.getSqrtPriceX96(StateLibraryTest.PoolId poolId) external returns (uint160) envfree;
    function PoolManager.getTick(StateLibraryTest.PoolId poolId) external returns (int24) envfree;
    function PoolManager.getProtocolFee(StateLibraryTest.PoolId poolId) external returns (uint24) envfree;
    function PoolManager.getLpFee(StateLibraryTest.PoolId poolId) external returns (uint24) envfree; 
    /// Liquidity
    function PoolManager.getLiquidity(StateLibraryTest.PoolId poolId) external returns (uint128) envfree;
    function PoolManager.getFeeGlobal0x128(StateLibraryTest.PoolId poolId) external returns (uint256) envfree;
    function PoolManager.getFeeGlobal1x128(StateLibraryTest.PoolId poolId) external returns (uint256) envfree;
    /// Tick
    function PoolManager.getTickLiquidityGross(StateLibraryTest.PoolId poolId, int24 tick) external returns (uint128) envfree;
    function PoolManager.getTickLiquidityNet(StateLibraryTest.PoolId poolId, int24 tick) external returns (int128) envfree;
    function PoolManager.getTickfeeGrowth0x128(StateLibraryTest.PoolId poolId, int24 tick) external returns (uint256) envfree;
    function PoolManager.getTickfeeGrowth1x128(StateLibraryTest.PoolId poolId, int24 tick) external returns (uint256) envfree;
    /// Positions
    function PoolManager.getPositionLiquidity(StateLibraryTest.PoolId poolId, bytes32 positionKey) external returns (uint128) envfree;
    function PoolManager.getPositionfeeGrowth0x128(StateLibraryTest.PoolId poolId, bytes32 positionKey) external returns (uint256) envfree;
    function PoolManager.getPositionfeeGrowth1x128(StateLibraryTest.PoolId poolId, bytes32 positionKey) external returns (uint256) envfree;
    /// TickBitmap
    function PoolManager.getTickBitmap(StateLibraryTest.PoolId poolId, int16 wordPos) external returns (uint256) envfree;
}
/*
┌────────────────────────────────────────────────────────────────────────────────────────────────────┐
| Equivalence test between StateLibrary lib access to PoolManager and access through Solidity harness|
└────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule getSlot0Equivalence(StateLibraryTest.PoolId poolId) {
    uint160 sqrtPriceX96; 
    int24 tick; 
    uint24 protocolFee; 
    uint24 lpFee;
    sqrtPriceX96, tick, protocolFee, lpFee = test.getSlot0(poolId);

    assert sqrtPriceX96 == PoolManager.getSqrtPriceX96(poolId);
    assert tick == PoolManager.getTick(poolId);
    assert protocolFee == PoolManager.getProtocolFee(poolId);
    assert lpFee == PoolManager.getLpFee(poolId);
}

rule getTickInfoEquivalence(StateLibraryTest.PoolId poolId, int24 tick) {
    uint128 liquidityGross;
    int128 liquidityNet;
    uint256 fee0;
    uint256 fee1;
    liquidityGross, liquidityNet, fee0, fee1 = test.getTickInfo(poolId, tick);

    assert liquidityGross == PoolManager.getTickLiquidityGross(poolId, tick);
    assert liquidityNet == PoolManager.getTickLiquidityNet(poolId, tick);
    assert fee0 == PoolManager.getTickfeeGrowth0x128(poolId, tick);
    assert fee1 == PoolManager.getTickfeeGrowth1x128(poolId, tick);
}

rule getTickLiquidityEquivalence(StateLibraryTest.PoolId poolId, int24 tick) {
    uint128 liquidityGross;
    int128 liquidityNet;
    liquidityGross, liquidityNet = test.getTickLiquidity(poolId, tick);

    assert liquidityGross == PoolManager.getTickLiquidityGross(poolId, tick);
    assert liquidityNet == PoolManager.getTickLiquidityNet(poolId, tick);
}

rule getFeeGrowthGlobalsEquivalence(StateLibraryTest.PoolId poolId) {
    uint256 feeGlobal0;
    uint256 feeGlobal1;
    feeGlobal0, feeGlobal1 = test.getFeeGrowthGlobals(poolId);

    assert feeGlobal0 == PoolManager.getFeeGlobal0x128(poolId);
    assert feeGlobal1 == PoolManager.getFeeGlobal1x128(poolId);
}

rule getTickFeeGrowthOutsideEquivalence(StateLibraryTest.PoolId poolId, int24 tick) {
    uint256 fee0;
    uint256 fee1;
    fee0, fee1 = test.getTickFeeGrowthOutside(poolId, tick);

    assert fee0 == PoolManager.getTickfeeGrowth0x128(poolId, tick);
    assert fee1 == PoolManager.getTickfeeGrowth1x128(poolId, tick);
}

rule getLiquidityEquivalence(StateLibraryTest.PoolId poolId) {
    uint128 liquidity = test.getLiquidity(poolId);

    assert liquidity == PoolManager.getLiquidity(poolId);
}

rule getPositionInfoEquivalence(StateLibraryTest.PoolId poolId, bytes32 positionId) {
    uint128 liquidity; uint256 feesInside0; uint256 feesInside1;
    liquidity, feesInside0, feesInside1 = test.getPositionInfo(poolId, positionId);

    assert liquidity == PoolManager.getPositionLiquidity(poolId, positionId);
    assert feesInside0 == PoolManager.getPositionfeeGrowth0x128(poolId, positionId);
    assert feesInside1 == PoolManager.getPositionfeeGrowth1x128(poolId, positionId);
}

rule getTickBitmapEquivalence(StateLibraryTest.PoolId poolId, int16 word) {
    uint256 bitmap = test.getTickBitmap(poolId, word);

    assert bitmap == PoolManager.getTickBitmap(poolId, word);
}

rule getPositionLiquidityEquivalence(StateLibraryTest.PoolId poolId, bytes32 positionId) {
    uint128 liquidity = test.getPositionLiquidity(poolId, positionId);

    assert liquidity == PoolManager.getPositionLiquidity(poolId, positionId);
}