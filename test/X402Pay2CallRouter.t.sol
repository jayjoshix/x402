// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/X402Pay2CallRouter.sol";
import "../src/examples/PremiumService.sol";
import "../src/interfaces/IERC20WithEIP3009.sol";

// Add interface to query USDC's domain separator
interface IUSDC {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

contract X402Pay2CallRouterTest is Test {
    X402Pay2CallRouter public router;
    PremiumService public service;
    IERC20WithEIP3009 public usdc;
    
    address constant USDC_BASE_SEPOLIA = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    address public treasury;
    address public alice;
    uint256 alicePrivateKey = 0xA11CE;
    
    function setUp() public {
        // Fork Base Sepolia
        vm.createSelectFork("https://sepolia.base.org");
        
        treasury = makeAddr("treasury");
        alice = vm.addr(alicePrivateKey);
        
        usdc = IERC20WithEIP3009(USDC_BASE_SEPOLIA);
        
        // Deploy router and service
        router = new X402Pay2CallRouter(USDC_BASE_SEPOLIA, treasury);
        service = new PremiumService(address(router));
        
        // Setup pricing and allowlist
        bytes4 selector = bytes4(keccak256("getPremiumBytes(address)"));
        router.setPrice(selector, 250_000); // $0.25
        router.allowTarget(address(service), true);
        
        // Give Alice some USDC (simulate faucet)
        deal(USDC_BASE_SEPOLIA, alice, 10_000_000); // $10 USDC
    }
    
    function testPayAndCall() public {
        uint256 value = 250_000; // $0.25
        uint256 validAfter = 0;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test-nonce-1");
        
        // Get USDC's actual domain separator
        bytes32 domainSeparator = IUSDC(USDC_BASE_SEPOLIA).DOMAIN_SEPARATOR();
        
        // Build EIP-712 signature with CORRECT typehash
        bytes32 RECEIVE_TYPEHASH = keccak256(
            "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
        );
        
        bytes32 structHash = keccak256(abi.encode(
            RECEIVE_TYPEHASH,
            alice,
            address(router),
            value,
            validAfter,
            validBefore,
            nonce
        ));
        
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        
        // Prepare call to service
        bytes memory data = abi.encodeWithSelector(
            service.getPremiumBytes.selector,
            alice
        );
        
        uint256 aliceBalBefore = usdc.balanceOf(alice);
        uint256 treasuryBalBefore = usdc.balanceOf(treasury);
        
        // Execute payAndCall
        (bool success, bytes memory returnData) = router.payAndCall(
            alice,
            value,
            validAfter,
            validBefore,
            nonce,
            v, r, s,
            address(service),
            data,
            false // no refund on failure
        );
        
        assertTrue(success);
        assertEq(usdc.balanceOf(alice), aliceBalBefore - value);
        assertEq(usdc.balanceOf(treasury), treasuryBalBefore + value);
        
        // Decode return data
        bytes memory result = abi.decode(returnData, (bytes));
        console.log("Service returned:", string(result));
    }
    
    function testCannotReuseNonce() public {
        uint256 value = 250_000;
        uint256 validAfter = 0;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test-nonce-2");
        
        (uint8 v, bytes32 r, bytes32 s) = _signPayment(alice, alicePrivateKey, value, validAfter, validBefore, nonce);
        
        bytes memory data = abi.encodeWithSelector(service.getPremiumBytes.selector, alice);
        
        // First call succeeds
        router.payAndCall(alice, value, validAfter, validBefore, nonce, v, r, s, address(service), data, false);
        
        // Second call with same nonce fails
        vm.expectRevert();
        router.payAndCall(alice, value, validAfter, validBefore, nonce, v, r, s, address(service), data, false);
    }
    
    function testUnauthorizedTargetReverts() public {
        address randomTarget = makeAddr("random");
        
        uint256 value = 250_000;
        uint256 validAfter = 0;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test-nonce-3");
        
        (uint8 v, bytes32 r, bytes32 s) = _signPayment(alice, alicePrivateKey, value, validAfter, validBefore, nonce);
        
        bytes memory data = abi.encodeWithSelector(service.getPremiumBytes.selector, alice);
        
        vm.expectRevert(X402Pay2CallRouter.NotAllowed.selector);
        router.payAndCall(alice, value, validAfter, validBefore, nonce, v, r, s, randomTarget, data, false);
    }
    
    // Helper functions
    function _signPayment(
        address from,
        uint256 fromPrivateKey,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        // Get USDC's actual domain separator
        bytes32 domainSeparator = IUSDC(USDC_BASE_SEPOLIA).DOMAIN_SEPARATOR();
        
        bytes32 RECEIVE_TYPEHASH = keccak256(
            "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
        );
        
        bytes32 structHash = keccak256(abi.encode(
            RECEIVE_TYPEHASH,
            from,
            address(router),
            value,
            validAfter,
            validBefore,
            nonce
        ));
        
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        return vm.sign(fromPrivateKey, digest);
    }
}
