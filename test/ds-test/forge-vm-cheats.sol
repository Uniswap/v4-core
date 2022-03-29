pragma solidity ^0.8.13;

interface Vm {
    function expectRevert(bytes calldata) external;
}