import "../Common/CVLMath.spec";

using ProtocolFeeLibraryTest as test;

methods {
    function test.getZeroForOneFee(uint24 fee) external returns (uint24) envfree;
    function test.getOneForZeroFee(uint24 fee) external returns (uint24) envfree;
    function test.isValidProtocolFee(uint24 fee) external returns (bool) envfree;
    function test.calculateSwapFee(uint16 self, uint24 lpFee) external returns (uint24) envfree;
    function test.MAX_PROTOCOL_FEE() external returns (uint24) envfree;
    function test.MAX_LP_FEE() external returns (uint24) envfree;
}

/// All rules are formal versions of the tests in test/libraries/ProtocolFeeLibrary.t.sol.

rule test_getZeroForOneFee() {
    uint24 fee = assert_uint24((assert_uint256(assert_uint256(MAX_PROTOCOL_FEE() - 1)) << 12) | assert_uint256(MAX_PROTOCOL_FEE()));
    assert test.getZeroForOneFee(fee) == MAX_PROTOCOL_FEE();
}

rule test_FV_getZeroForOneFee(uint24 fee) {
    assert test.getZeroForOneFee(fee) == assert_uint24(fee % 4096);
}

rule test_getOneForZeroFee() {
    uint24 fee = assert_uint24((assert_uint256(assert_uint256(MAX_PROTOCOL_FEE() - 1)) << 12) | assert_uint256(MAX_PROTOCOL_FEE()));
    assert test.getOneForZeroFee(fee) == assert_uint24(MAX_PROTOCOL_FEE() - 1);
}

rule test_FV_getOneForZeroFee(uint24 fee) {
    assert assert_uint256(test.getOneForZeroFee(fee)) == assert_uint256(fee >> 12);
}

rule test_FV_isValidProtocolFee_fee(uint24 fee) {
    if (((assert_uint256(fee) >> 12) > assert_uint256(MAX_PROTOCOL_FEE())) || (fee % 4096 > to_mathint(MAX_PROTOCOL_FEE()))) {
        assert !test.isValidProtocolFee(fee);
    } else {
        assert test.isValidProtocolFee(fee);
    }
    assert true;
}

rule test_FV_calculateSwapFee(uint16 self, uint24 lpFee) {
    require self <= MAX_PROTOCOL_FEE();
    require lpFee <= MAX_LP_FEE();

    uint24 swapFee = test.calculateSwapFee(self, lpFee);
    // if lp fee is not the max, the swap fee should never be the max since the protocol fee is taken off first and then the lp fee is taken from the remaining amount
    if (lpFee < MAX_LP_FEE()) {
        assert swapFee <= MAX_LP_FEE();
    } else {
        assert swapFee == MAX_LP_FEE();
    }

    // Equivalent to protocolFee + lpFee(1_000_000 - protocolFee) / 1_000_000 (rounded up)
    mathint expectedSwapFee = self + mulDivUpCVL(lpFee, assert_uint256(MAX_LP_FEE() - self), MAX_LP_FEE());

    assert to_mathint(swapFee) == expectedSwapFee;

    assert swapFee >= self;
}
