import "../Common/CVLMath.spec";

methods {
    function UnsafeMath.divRoundingUp(uint256 x, uint256 y) internal returns (uint256) => divUpCVL(x,y);
    function UnsafeMath.simpleMulDiv(uint256 x, uint256 y, uint256 z) internal returns (uint256) => mulDivDownCVL(x,y,z);
}
