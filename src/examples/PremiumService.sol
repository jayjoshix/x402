// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PremiumService {
    address public immutable router;

    constructor(address _router) {
        router = _router;
    }

    modifier onlyRouter() {
        require(msg.sender == router, "only router");
        _;
    }

    // Example paid function; price is enforced by the router
    function getPremiumBytes(address user) external onlyRouter returns (bytes memory) {
        return abi.encodePacked("hello,", user);
    }
}
