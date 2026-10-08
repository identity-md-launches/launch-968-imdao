// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract PolicyV1 {
    function weights() external pure returns (uint256 development, uint256 reserve) {
        return (8000, 2000);
    }
}

contract PolicyV2 {
    function weights() external pure returns (uint256 development, uint256 reserve) {
        return (6000, 4000);
    }
}

library PolicyReader {
    /// @dev Fixed output buffer, no unbounded returndatacopy, gas-limited STATICCALL.
    function read(address policy) internal view returns (uint256 development, uint256 reserve) {
        bytes memory input = abi.encodeWithSelector(PolicyV1.weights.selector);
        bool ok;
        uint256 size;
        assembly ("memory-safe") {
            let output := mload(0x40)
            mstore(output, 0)
            mstore(add(output, 32), 0)
            ok := staticcall(30000, policy, add(input, 32), mload(input), output, 64)
            size := returndatasize()
            development := mload(output)
            reserve := mload(add(output, 32))
        }
        if (!ok || size != 64 || development > 10000 || reserve > 10000) return (8000, 2000);
        if (development + reserve != 10000) return (8000, 2000);
    }
}
