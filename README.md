# x402 Pay2Call Router: Atomic Payment Gateway for On-Chain Commerce

> A Solidity-native x402 implementation enabling trustless, usage-based monetization for dapps and AI agents via atomic USDC payment settlement and immediate function execution on Base and EVM networks.

## 📋 Table of Contents

- [About](#about)
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security](#security)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

## About

The x402 Pay2Call Router is an on-chain atomic payment gateway that pulls USDC using EIP-3009 meta-transaction signatures and immediately executes target smart-contract functions in the same transaction. It enables per-call pricing, instant settlement, and programmatic access aligned with the HTTP 402 "Payment Required" model behind the x402 protocol.

**Perfect for:**
- API monetization (charge per request)
- Oracle price feeds (usage-based pricing)
- Smart contract audit services
- AI agent-to-agent commerce
- Blockchain DeFi tools and analytics

### Why This Matters

Traditional payment systems charge 2.9% + $0.30 per transaction, making micropayments economically unviable. This router settles payments on Base L2 for under $0.01, unlocking granular usage-based billing for the first time while maintaining complete trustlessness and deterministic verification on-chain.

## ✨ Features

- **Atomic Payment + Execution**: EIP-3009 USDC settlement and target function call occur in the same transaction—no race conditions, no off-chain coordination[11][12]
- **Safer Meta-Transactions**: Uses `receiveWithAuthorization` variant to prevent front-running attacks that can occur with `transferWithAuthorization` in contract flows[12]
- **Per-Function Pricing**: Configure price per ABI selector for granular monetization of individual endpoints[11]
- **Target Allowlist**: Restrict callable contracts to minimize misuse and simplify security audits[13]
- **Revenue Splits**: Distribute fees across multiple recipients in basis points with automatic treasury payouts[13]
- **Optional Refunds**: Automatically refund undistributed remainder if downstream call fails[13]
- **Verifiable Billing**: All transactions recorded on-chain; transparent, deterministic accounting with no chargebacks[14]
- **AI Agent Ready**: Agents sign payments programmatically without accounts or key exchange, enabling trustless machine-to-machine commerce[15][16]

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Client (dApp/AI Agent)                   │
│                                                              │
│  1. Sign EIP-712 ReceiveWithAuthorization payload           │
│  2. Call payAndCall(from, value, nonce, sig, target, data)  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│           X402Pay2CallRouter (On-Chain)                     │
│                                                              │
│  • Validate selector price & allowlist                      │
│  • Call USDC.receiveWithAuthorization() (EIP-3009)          │
│  • Distribute revenue (basis point splits)                  │
│  • Execute target function via low-level call               │
│  • Emit PaidAndCalled event (for reputation tracking)       │
│  • Optionally refund on failure                             │
└────────────────────┬────────────────────────────────────────┘
                     │
      ┌──────────────┴──────────────┐
      ▼                             ▼
 ┌─────────────┐          ┌──────────────────┐
 │ USDC Token  │          │ Target Service   │
 │ (EIP-3009)  │          │ (Premium func)   │
 │             │          │                  │
 │ Settles fee │          │ Executes logic   │
 └─────────────┘          └──────────────────┘
```

**Three-layer design:**
1. **Client Layer**: Sign EIP-712 authorization with user's private key
2. **Settlement Layer**: Router pulls USDC via receiveWithAuthorization (front-run safe)
3. **Execution Layer**: Router calls target function; emits events for off-chain reputation aggregation

## 📦 Prerequisites

- **Foundry** ([install](https://getfoundry.sh/))
- **Git**
- **Node.js** (v18+, for client integration)
- Base Sepolia testnet ETH or local Anvil instance
- Base Sepolia testnet USDC (or test USDC contract)

## 🚀 Installation

### Clone the Repository

```bash
git clone https://github.com/yourusername/x402-pay2call-router.git
cd x402-pay2call-router
```

### Install Dependencies

```bash
forge install
```

This installs:
- `openzeppelin/openzeppelin-contracts` (ERC20, access control)
- `transmissions11/solmate` (optimized utilities)

### Verify Installation

```bash
forge build
```

Expected output: `Compiler run successful!`

## ⚡ Quick Start



## 💡 Usage

### Example: Payment-Gated API Call

#### 1. Client Signs Payment Authorization (Off-Chain)

```javascript
import { createWalletClient, http } from 'viem';
import { baseSepolia } from 'viem/chains';
import crypto from 'crypto';

const client = createWalletClient({
  account: privateKeyToAccount(BUYER_PRIVATE_KEY),
  chain: baseSepolia,
  transport: http()
});

// Get USDC's domain separator
const domainSeparator = await publicClient.readContract({
  address: USDC_ADDRESS,
  abi: [{ name: 'DOMAIN_SEPARATOR', outputs: [{ type: 'bytes32' }] }],
  functionName: 'DOMAIN_SEPARATOR'
});

// Sign EIP-712 ReceiveWithAuthorization
const signature = await client.signTypedData({
  domain: {
    name: 'USD Coin',
    version: '2',
    chainId: 84532,
    verifyingContract: USDC_ADDRESS
  },
  types: {
    ReceiveWithAuthorization: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'validAfter', type: 'uint256' },
      { name: 'validBefore', type: 'uint256' },
      { name: 'nonce', type: 'bytes32' }
    ]
  },
  primaryType: 'ReceiveWithAuthorization',
  message: {
    from: userAddress,
    to: ROUTER_ADDRESS,
    value: 250000n, // $0.25 in USDC (6 decimals)
    validAfter: 0n,
    validBefore: BigInt(Math.floor(Date.now() / 1000) + 3600),
    nonce: `0x${crypto.randomBytes(32).toString('hex')}`
  }
});
```

#### 2. Call Router with Payment

```solidity
// In Solidity or via ethers.js
const tx = await router.payAndCall(
  userAddress,
  250000, // $0.25 USDC
  0,
  validBefore,
  nonce,
  v, r, s,
  SERVICE_ADDRESS,
  abi.encodeWithSelector(
    service.getPremiumBytes.selector,
    userAddress
  ),
  false // don't refund on failure
);

await tx.wait();
```

#### 3. Router Executes Atomically

1. **Verify signature** via EIP-712 recovery
2. **Pull USDC** via `receiveWithAuthorization` (safe from front-running)
3. **Distribute revenue** to treasury and optional splits
4. **Call service function** (getPremiumBytes)
5. **Emit PaidAndCalled event** with success status

### Configure Custom Pricing

```bash
# Set price for a new function selector
cast send --rpc-url $BASE_SEPOLIA_RPC \
  $ROUTER_ADDRESS \
  "setPrice(bytes4,uint256)" \
  0x4a4cd423 \
  250000
```

### Add Revenue Splits

```bash
# Pay 50% to recipient, 50% to treasury
cast send --rpc-url $BASE_SEPOLIA_RPC \
  $ROUTER_ADDRESS \
  "setSplits((address,uint16)[])" \
  '[{"recipient":"0x123...","bps":5000}]'
```

## 🧪 Testing

### Run Full Test Suite

```bash
forge test -vv
```

### Run with Gas Report

```bash
forge test --gas-report
```

### Run Specific Test

```bash
forge test --match testPayAndCall -vvv
```

### Fork Testing Against Base Sepolia

```bash
forge test --fork-url https://sepolia.base.org -vv
```

**Test Coverage:**
- ✅ Atomic payment + execution
- ✅ Nonce replay protection
- ✅ Target allowlist enforcement
- ✅ Price validation
- ✅ Revenue distribution
- ✅ Optional refunds

## 🌐 Deployment

### Deploy to Base Sepolia

#### Prerequisites

1. Get Base Sepolia ETH: https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet
2. Get BaseScan API key: https://sepolia.basescan.org/apis
3. Set environment variables:

```bash
export PRIVATE_KEY=your_private_key
export TREASURY_ADDRESS=your_wallet
export USDC_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e
export BASE_SEPOLIA_RPC=https://sepolia.base.org
export BASESCAN_API_KEY=your_api_key
```

#### Deploy and Verify

```bash
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $BASE_SEPOLIA_RPC \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvv
```

#### View on BaseScan

```
https://sepolia.basescan.org/address/YOUR_ROUTER_ADDRESS
```

### Production Deployment (Base Mainnet)

```bash
export BASE_MAINNET_RPC=https://mainnet.base.org
export USDC_ADDRESS=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 # Native USDC

forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $BASE_MAINNET_RPC \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvv
```

## 🔒 Security

### Architecture Security

- **EIP-3009 receiveWithAuthorization**: Only the intended recipient (router) can settle the signature, preventing front-running attacks that plague `transferWithAuthorization`[12]
- **Nonce tracking**: Each authorization is marked used after execution, preventing replay attacks[12]
- **ReentrancyGuard**: Protects against reentrancy in payment distribution[13]
- **Selector validation**: Enforces exact price per function to prevent underpayment[11]
- **Time window validation**: EIP-712 signatures include `validAfter` and `validBefore` to limit exposure[12]

### Best Practices

1. **Always query USDC's DOMAIN_SEPARATOR** rather than recomputing; it's cached at deployment[12]
2. **Use short validity windows** (30-60 minutes) to reduce signature exposure[11]
3. **Rotate nonces aggressively** to prevent nonce collision attacks[12]
4. **Test signatures with actual token** before production (chain ID mismatch is a common error)[12]
5. **Audit before mainnet deployment** - recommend professional smart contract audit for production use[14]

### Known Limitations

- EIP-3009 is token-specific; verify target token implements receiveWithAuthorization
- Refund-on-failure only returns undistributed remainders; define off-chain refund policies for partial failures
- Time drift between client and RPC can cause signature expiry; synchronize clocks

## 🛣 Roadmap

- [ ] ERC-8004 Trustless Agents integration (agent identity + reputation)
- [ ] Post-paid credit flows with spending caps
- [ ] TEE attestation support for privacy-preserving payments
- [ ] Cross-chain settlement via LayerZero or Hyperlane
- [ ] Automated metering via oracles for real-time usage tracking
- [ ] DAO governance for pricing and policy updates
- [ ] Mobile SDK for agent wallets

## 🤝 Contributing

Contributions welcome! Please follow this workflow:

1. **Fork** the repository
2. **Create a feature branch**: `git checkout -b feature/awesome-feature`
3. **Make changes** and add tests
4. **Run tests**: `forge test`
5. **Commit**: `git commit -m 'Add awesome feature'`
6. **Push**: `git push origin feature/awesome-feature`
7. **Open a Pull Request**

### Code Style

- Use Solidity 0.8.20+
- Follow [OpenZeppelin style guide](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/CONTRIBUTING.md#code-style)
- Document complex logic with NatSpec comments
- Include tests for all new functions



## 🙏 Acknowledgments

- [x402 Protocol](https://www.x402.org) by Coinbase for the HTTP 402 "Payment Required" standard
- [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) by Dave Hoag for meta-transaction authorization
- [Foundry](https://getfoundry.sh) for smart contract development
- [OpenZeppelin](https://www.openzeppelin.com) for battle-tested contract libraries
- Base team for low-cost, fast EVM execution

***

**Built for trustless, usage-based commerce on Base and EVM networks. Enable AI agents and dapps to transact with zero friction, infinite scale.** 🚀

