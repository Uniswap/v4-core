// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

contract MockContract {
    mapping(bytes32 => uint256) public calls;
    mapping(bytes32 => mapping(bytes => uint256)) public callParams;

    function timesCalled(string calldata fnSig) public view returns (uint256) {
        bytes32 selector = bytes32(uint256(keccak256(bytes(fnSig))) & (type(uint256).max << 224));
        return calls[selector];
    }

    function calledWith(string calldata fnSig, bytes calldata params) public view returns (bool) {
        bytes32 selector = bytes32(uint256(keccak256(bytes(fnSig))) & (type(uint256).max << 224));
        return callParams[selector][params[1:]] > 0; // Drop 0x byte string prefix
    }

    fallback() external {
        bytes32 selector = bytes32(msg.data[:5]);
        bytes memory params = msg.data[5:];
        calls[selector]++;
        callParams[selector][params]++;
    }
}
