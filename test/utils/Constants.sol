// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Constants {
    /// @dev All sqrtPrice calculations are calculated as
    /// sqrtPriceX96 = floor(sqrt(A / B) * 2 ** 96) where A and B are the currency reserves
    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint160 public constant SQRT_PRICE_1_2 = 56022770974786139918731938227;
    uint160 public constant SQRT_PRICE_1_4 = 39614081257132168796771975168;
    uint160 public constant SQRT_PRICE_2_1 = 112045541949572279837463876454;
    uint160 public constant SQRT_PRICE_4_1 = 158456325028528675187087900672;
    uint160 public constant SQRT_PRICE_121_100 = 87150978765690771352898345369;
    uint160 public constant SQRT_PRICE_99_100 = 78831026366734652303669917531;
    uint160 public constant SQRT_PRICE_99_1000 = 24928559360766947368818086097;
    uint160 public constant SQRT_PRICE_101_100 = 79623317895830914510639640423;
    uint160 public constant SQRT_PRICE_1000_100 = 250541448375047931186413801569;
    uint160 public constant SQRT_PRICE_1010_100 = 251791039410471229173201122529;
    uint160 public constant SQRT_PRICE_10000_100 = 792281625142643375935439503360;

    uint256 constant MAX_UINT256 = type(uint256).max;
    uint128 constant MAX_UINT128 = type(uint128).max;
    uint160 constant MAX_UINT160 = type(uint160).max;

    address constant ADDRESS_ZERO = address(0);

    /// 0011 1111 1111 1111
    address payable constant ALL_HOOKS = payable(0x0000000000000000000000000000000000003fFF);

    uint256 constant TICKS_OFFSET = 4;

    uint24 constant FEE_LOW = 500;
    uint24 constant FEE_MEDIUM = 3000;
    uint24 constant FEE_HIGH = 10000;

    bytes constant ZERO_BYTES = new bytes(0);
}
