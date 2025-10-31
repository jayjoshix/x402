// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/X402Pay2CallRouter.sol";
import "../src/examples/PremiumService.sol";

contract DeployScript is Script {
    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        // Example: Base Sepolia USDC (update for your network)
        address usdc = vm.envAddress("USDC_ADDRESS");

        vm.startBroadcast(key);
        X402Pay2CallRouter router = new X402Pay2CallRouter(usdc, treasury);
        PremiumService svc = new PremiumService(address(router));

        // Wire pricing and allowlist
        // selector of PremiumService.getPremiumBytes(address) is computed here:
        bytes4 sel = bytes4(keccak256("getPremiumBytes(address)"));
        router.setPrice(sel, 250_000); // $0.25 in 6‑dec USDC units
        router.allowTarget(address(svc), true);
        vm.stopBroadcast();

        console.log("Router:", address(router));
        console.log("Service:", address(svc));
    }
}
