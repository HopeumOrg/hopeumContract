# Hopeum Staking Contracts

This repository contains the smart contracts for the Hopeum staking ecosystem built on Ethereum using Solidity ^0.8.23.

## 📋 Table of Contents

- [Overview](#overview)
- [Contract Architecture](#contract-architecture)
- [StakingPools Contract](#stakingpools-contract)
- [Deployment](#deployment)
- [Usage](#usage)
- [Security Features](#security-features)
- [Development Setup](#development-setup)

## 🔍 Overview

The Hopeum staking system provides a flexible, secure platform for creating and managing multiple staking pools with different parameters. Users can stake various tokens (including native ETH) to earn rewards over time, with optional collateral token minting for liquidity purposes.

### Key Features

- **Multi-Pool Support**: Create unlimited staking pools with different parameters
- **Native ETH & ERC20 Support**: Stake both ETH and any ERC20 token
- **Flexible APY**: Customizable Annual Percentage Yield for each pool
- **Collateral Tokens**: Optional mintable collateral tokens for staked assets
- **Time-Based Rewards**: Rewards calculated based on staking duration
- **Emergency Controls**: Global and per-pool pause mechanisms
- **Secure Architecture**: Built with OpenZeppelin standards

## 🏗️ Contract Architecture

### Core Contracts

1. **StakingPools.sol** - Main staking contract managing all pools and user interactions
2. **RewardBank.sol** - Simple treasury contract for reward token management
3. **stHPM.sol** - Example collateral token contract (mintable/burnable)

### Dependencies

- OpenZeppelin Contracts v5.x
- Foundry for development and testing

## 📈 StakingPools Contract

The `StakingPools` contract is the heart of the system, providing comprehensive staking functionality.

### Pool Structure

Each staking pool contains the following parameters:

```solidity
struct Pool {
    address stakeToken;        // Token to be staked (address(0) for ETH)
    address rewardToken;       // Token distributed as rewards
    uint256 apy;              // Annual percentage yield (basis points)
    uint256 duration;         // Pool duration in seconds
    uint256 startTime;        // Pool start timestamp
    uint256 endTime;          // Pool end timestamp
    uint256 totalStaked;      // Total amount currently staked
    bool isPaused;            // Pool pause status
    bool isActive;            // Pool active status
    bool canWithdrawStake;    // Whether early withdrawal is allowed
    uint256 minStakeAmount;   // Minimum stake requirement
    bool isCollateralized;    // Collateral token feature enabled
    address collateralToken;  // Collateral token address
    bool isNative;            // ETH staking pool
    uint8 collateralTokenDecimals;
    uint256 collateralPrice;  // Collateral minting ratio
}
```

### Core Functions

#### Pool Management (Owner Only)

- `createPool()` - Create a new staking pool
- `updatePoolAPY()` - Modify pool APY
- `pausePool()/resumePool()` - Control pool operations
- `closePool()` - Permanently disable a pool
- `extendPoolDuration()` - Extend pool duration

#### User Functions

- `stake()` - Stake tokens in a pool
- `withdraw()` - Withdraw staked tokens (if allowed)
- `claimReward()` - Claim accumulated rewards
- `emergencyWithdraw()` - Emergency withdrawal (forfeit rewards)

#### View Functions

- `getPoolInfo()` - Get complete pool information
- `getUserStakeInfo()` - Get user stake details and pending rewards
- `calculateReward()` - Calculate pending rewards for a user
- `getActivePools()` - List all active pools

### Reward Calculation

Rewards are calculated using a time-based formula:

```
reward = (stakedAmount × APY × timeElapsed) / (365 days × 10000)
```

Where:

- `APY` is in basis points (e.g., 500 = 5%)
- `timeElapsed` is in seconds
- Rewards accrue from the last claim time or staking time

### Collateral Token System

For pools with `isCollateralized = true`:

1. **Minting**: When users stake, collateral tokens are minted proportionally
2. **Burning**: When users withdraw, equivalent collateral tokens are burned
3. **Price Ratio**: Configurable ratio determines collateral amount per staked token

Example: If collateral price is `0.003` (3000000000000000 wei for 18 decimals), staking 1 ETH mints 0.003 collateral tokens.

## 🚀 Deployment

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy Script Example

```solidity
// scripts/DeployStaking.s.sol
contract DeployStaking is Script {
    function run() external {
        vm.startBroadcast();

        StakingPools stakingPools = new StakingPools();
        RewardBank rewardBank = new RewardBank();

        vm.stopBroadcast();
    }
}
```

### Deploy to Network

```bash
forge script script/DeployStaking.s.sol:DeployStaking \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

## 💡 Usage Examples

### Creating a Staking Pool

```solidity
// Create ETH staking pool with 5% APY
uint256 poolId = stakingPools.createPool(
    address(0),           // ETH (native)
    rewardTokenAddress,   // Reward token
    500,                  // 5% APY (basis points)
    365 days,            // 1 year duration
    block.timestamp,     // Start immediately
    true,                // Allow withdrawals
    0.1 ether,          // Minimum 0.1 ETH stake
    false,              // No collateral
    address(0),         // No collateral token
    true,               // Native ETH pool
    0                   // No collateral price
);
```

### Staking Tokens

```solidity
// Stake ETH
stakingPools.stake{value: 1 ether}(poolId, 0);

// Stake ERC20 tokens
IERC20(tokenAddress).approve(address(stakingPools), amount);
stakingPools.stake(poolId, amount);
```

### Claiming Rewards

```solidity
// Check pending rewards
uint256 pending = stakingPools.calculateReward(poolId, userAddress);

// Claim rewards
stakingPools.claimReward(poolId);
```

## 🔒 Security Features

### Access Control

- **Owner Controls**: Pool creation, parameter updates, emergency functions
- **User Permissions**: Only stake owners can withdraw their funds

### Reentrancy Protection

- All state-changing functions use `nonReentrant` modifier
- Safe token transfers using OpenZeppelin's SafeERC20

### Pause Mechanisms

- **Global Pause**: Emergency stop for entire system
- **Pool-Level Pause**: Individual pool suspension
- **Emergency Withdrawal**: Always available regardless of pause state

### Input Validation

- Comprehensive parameter validation
- Time-based constraints enforcement
- Balance and allowance checks

### Economic Security

- Reward calculations prevent overflow/underflow
- Collateral token burning prevents double-spending
- Minimum stake amounts prevent spam attacks

## 🛠️ Development Setup

### Local Development

```bash
# Clone repository
git clone <repository-url>
cd contracts

# Install dependencies
forge install

# Run tests
forge test -vvv

# Run with gas reporting
forge test --gas-report

# Coverage report
forge coverage
```

### Testing

The contract includes comprehensive tests covering:

- Pool creation and management
- Staking and withdrawal flows
- Reward calculations and claims
- Collateral token mechanics
- Emergency scenarios
- Access control
- Edge cases and error conditions

### Code Formatting

```bash
# Format code
forge fmt

# Check formatting
forge fmt --check
```

### Gas Optimization

```bash
# Generate gas snapshots
forge snapshot

# Compare gas usage
forge snapshot --diff .gas-snapshot
```

## ⚠️ Disclaimer

These contracts are provided as-is. Please conduct thorough testing and auditing before deploying to mainnet. The developers assume no responsibility for any losses incurred through the use of these contracts.
