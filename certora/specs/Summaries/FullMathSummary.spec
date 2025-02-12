import "../Common/CVLMath.spec";

methods {
    function FullMath.mulDiv(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => mulDivDownCVL(a,b,denominator);
    function FullMath.mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => mulDivUpCVL(a,b,denominator);
}
