using Slot0Test as test;
methods {
    // #### GETTERS ####
    function sqrtPriceX96() external returns (uint160) envfree;
    function tick() external returns (int24) envfree;
    function protocolFee() external returns (uint24) envfree;
    function lpFee() external returns (uint24) envfree;

    // #### SETTERS ####
    function setSqrtPriceX96(uint160 _sqrtPriceX96) external envfree;
    function setTick(int24 _tick) external envfree;
    function setProtocolFee(uint24 _protocolFee) external envfree;
    function setLpFee(uint24 _lpFee) external envfree;
}

rule setSqrtPriceX96_integrity(uint160 _sqrtPriceX96) {
    uint160 sqrtPrice_pre = sqrtPriceX96();
    int24 tick_pre = tick();
    uint24 protocolFee_pre = protocolFee();
    uint24 lpFee_pre = lpFee();
        setSqrtPriceX96@withrevert(_sqrtPriceX96);
        bool reverted = lastReverted;
    uint160 sqrtPrice_post = sqrtPriceX96();
    int24 tick_post = tick();
    uint24 protocolFee_post = protocolFee();
    uint24 lpFee_post = lpFee();

    assert !reverted;
    assert sqrtPrice_post == _sqrtPriceX96;
    assert tick_pre == tick_post;
    assert protocolFee_pre == protocolFee_post;
    assert lpFee_pre == lpFee_post;
}

rule setTick_integrity(int24 _tick) {
    uint160 sqrtPrice_pre = sqrtPriceX96();
    int24 tick_pre = tick();
    uint24 protocolFee_pre = protocolFee();
    uint24 lpFee_pre = lpFee();
        setTick@withrevert(_tick);
        bool reverted = lastReverted;
    uint160 sqrtPrice_post = sqrtPriceX96();
    int24 tick_post = tick();
    uint24 protocolFee_post = protocolFee();
    uint24 lpFee_post = lpFee();

    assert !reverted;
    assert sqrtPrice_post == sqrtPrice_pre;
    assert tick_post == _tick;
    assert protocolFee_pre == protocolFee_post;
    assert lpFee_pre == lpFee_post;
}

rule setProtocolFee_integrity(uint24 _protocolFee) {
    uint160 sqrtPrice_pre = sqrtPriceX96();
    int24 tick_pre = tick();
    uint24 protocolFee_pre = protocolFee();
    uint24 lpFee_pre = lpFee();
        setProtocolFee@withrevert(_protocolFee);
        bool reverted = lastReverted;
    uint160 sqrtPrice_post = sqrtPriceX96();
    int24 tick_post = tick();
    uint24 protocolFee_post = protocolFee();
    uint24 lpFee_post = lpFee();

    assert !reverted;
    assert sqrtPrice_post == sqrtPrice_pre;
    assert tick_pre == tick_post;
    assert protocolFee_post == _protocolFee;
    assert lpFee_pre == lpFee_post;
}

rule setLPFee_integrity(uint24 _lpFee) {
    uint160 sqrtPrice_pre = sqrtPriceX96();
    int24 tick_pre = tick();
    uint24 protocolFee_pre = protocolFee();
    uint24 lpFee_pre = lpFee();
        setLpFee@withrevert(_lpFee);
        bool reverted = lastReverted;
    uint160 sqrtPrice_post = sqrtPriceX96();
    int24 tick_post = tick();
    uint24 protocolFee_post = protocolFee();
    uint24 lpFee_post = lpFee();

    assert !reverted;
    assert sqrtPrice_post == sqrtPrice_pre;
    assert tick_pre == tick_post;
    assert protocolFee_post == protocolFee_pre;
    assert lpFee_post == _lpFee;
}