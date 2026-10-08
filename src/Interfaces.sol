// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IGovernorWiring {
    function timelock() external view returns (address);
    function treasury() external view returns (address);
    function hook() external view returns (address);
    function oracle() external view returns (address);
    function imd() external view returns (address);
    function validateAction(address target, bytes calldata data) external view;
}

interface IHookWiring {
    function treasury() external view returns (address);
    function manager() external view returns (address);
    function timelock() external view returns (address);
    function policyV1() external view returns (address);
    function policyV2() external view returns (address);
    function takeFee(address asset, uint256 amount) external;
}

interface ILockWiring {
    function frozen() external view returns (bool);
}

interface IOracleWiring {
    function timelock() external view returns (address);
    function delivery() external view returns (address);
}

interface IDeliveryWiring {
    function responder() external view returns (address);
}

interface IRouterWiring {
    function manager() external view returns (address);
    function hook() external view returns (address);
}
