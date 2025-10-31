// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IERC20WithEIP3009.sol";

contract X402Pay2CallRouter is ReentrancyGuard {
    IERC20WithEIP3009 public immutable USDC;
    address public treasury;

    mapping(bytes4 => uint256) public priceForSelector;
    mapping(address => bool) public allowedTarget;

    struct Split {
        address recipient;
        uint16 bps;
    }
    Split[] public splits;
    uint16 public totalBps;

    event PaidAndCalled(address indexed user, address indexed target, bytes4 indexed selector, uint256 price, bool success, bytes returnData);
    event RefundIssued(address indexed user, uint256 amount);
    event TargetAllowed(address target, bool allowed);
    event PriceSet(bytes4 selector, uint256 price);
    event TreasuryUpdated(address oldT, address newT);
    event SplitsUpdated();

    error NotAllowed();
    error BadSplit();
    error BadTreasury();
    error InvalidPrice();
    error NothingToRefund();

    constructor(address usdc, address _treasury) {
        require(usdc != address(0) && _treasury != address(0), "zero");
        USDC = IERC20WithEIP3009(usdc);
        treasury = _treasury;
    }

    function setTreasury(address t) external {
        if (t == address(0)) revert BadTreasury();
        address old = treasury;
        treasury = t;
        emit TreasuryUpdated(old, t);
    }

    function allowTarget(address t, bool allowed) external {
        allowedTarget[t] = allowed;
        emit TargetAllowed(t, allowed);
    }

    function setPrice(bytes4 selector, uint256 price) external {
        priceForSelector[selector] = price;
        emit PriceSet(selector, price);
    }

    function setSplits(Split[] calldata newSplits) external {
        delete splits;
        uint256 len = newSplits.length;
        uint32 sum;
        for (uint256 i; i < len; ++i) {
            splits.push(newSplits[i]);
            sum += newSplits[i].bps;
            if (newSplits[i].recipient == address(0)) revert BadSplit();
        }
        if (sum > 10_000) revert BadSplit();
        totalBps = uint16(sum);
        emit SplitsUpdated();
    }

    function payAndCall(
        address from,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v, bytes32 r, bytes32 s,
        address target,
        bytes calldata data,
        bool refundOnFailure
    ) external nonReentrant returns (bool ok, bytes memory ret) {
        if (!allowedTarget[target]) revert NotAllowed();

       require(data.length >= 4, "Invalid data");
bytes4 sel = bytes4(data[0:4]);
        uint256 requiredPrice = priceForSelector[sel];
        if (requiredPrice == 0 || value < requiredPrice) revert InvalidPrice();

        USDC.receiveWithAuthorization(
            from,
            address(this),
            value,
            validAfter, validBefore, nonce,
            v, r, s
        );

        _distribute(value);

        (ok, ret) = target.call(data);

        if (!ok && refundOnFailure) {
            uint256 bal = USDC.balanceOf(address(this));
            uint256 refundable = bal;
            if (refundable > 0) {
                _safeUSDCTransfer(from, refundable);
                emit RefundIssued(from, refundable);
            } else {
                revert NothingToRefund();
            }
        }

        emit PaidAndCalled(from, target, sel, requiredPrice, ok, ret);
    }

    function _distribute(uint256 amount) internal {
        uint256 len = splits.length;
        if (len == 0) {
            _safeUSDCTransfer(treasury, amount);
            return;
        }
        uint256 distributed;
        for (uint256 i; i < len; ++i) {
            uint256 part = (amount * splits[i].bps) / 10_000;
            if (part > 0) {
                _safeUSDCTransfer(splits[i].recipient, part);
                distributed += part;
            }
        }
        uint256 leftover = amount - distributed;
        if (leftover > 0) _safeUSDCTransfer(treasury, leftover);
    }

    function _safeUSDCTransfer(address to, uint256 amount) internal {
        (bool s, ) = address(USDC).call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(s, "USDC transfer failed");
    }
}
