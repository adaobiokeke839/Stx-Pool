# Decentralized Collateral Lending Protocol (DCLP)

A trustless DeFi lending protocol built on the Stacks blockchain that enables users to deposit STX tokens as collateral and mint loans against their holdings. The protocol enforces over-collateralization requirements and implements automatic liquidation mechanisms to maintain system stability.

## Overview

The DCLP protocol allows users to:
- Deposit STX tokens as collateral
- Borrow against their collateral at a maximum 66.67% loan-to-value ratio
- Maintain positions with real-time health monitoring
- Participate in liquidations when positions become undercollateralized

Users retain full control of their collateral until liquidation conditions are triggered, creating a secure and transparent lending environment.

## Key Features

### **Over-Collateralized Lending**
- Minimum 150% collateral ratio required
- Maximum borrowing capacity: 66.67% of collateral value

### **Automatic Liquidation System**
- Liquidation triggered at 130% collateral ratio
- Liquidators receive all collateral as incentive
- Prevents protocol insolvency

### **Dynamic Pricing**
- Oracle-based price feeds for accurate valuations
- Real-time position health monitoring
- Transparent collateral ratio calculations

### **Governance Controls**
- Fee structure management (max 10%)
- Price oracle updates
- Ownership transfer capabilities

### **Analytics & Reporting**
- Comprehensive protocol metrics
- Position health factors
- Utilization rate tracking

## Protocol Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Minimum Collateral Ratio | 150% | Required overcollateralization |
| Liquidation Threshold | 130% | Automatic liquidation trigger |
| Maximum Fee Rate | 10% | Upper limit for protocol fees |
| Default Fee Rate | 1% | Initial borrowing fee |

## Contract Functions

### Position Management

#### `create-lending-position()`
Creates a new lending position for the caller.
- **Access**: Public
- **Returns**: `(response bool uint)`

#### `deposit-collateral(stx-amount)`
Deposits STX tokens as collateral to an existing position.
- **Parameters**: `stx-amount` (uint) - Amount of STX to deposit
- **Access**: Public
- **Returns**: `(response bool uint)`

#### `withdraw-collateral(stx-amount)`
Withdraws excess collateral while maintaining minimum ratio.
- **Parameters**: `stx-amount` (uint) - Amount of STX to withdraw
- **Access**: Public
- **Returns**: `(response bool uint)`

### Borrowing & Repayment

#### `borrow-against-collateral(loan-amount)`
Borrows against deposited collateral.
- **Parameters**: `loan-amount` (uint) - Amount to borrow in microSTX
- **Access**: Public
- **Returns**: `(response bool uint)`

#### `repay-loan(repayment-amount)`
Repays outstanding debt with fees.
- **Parameters**: `repayment-amount` (uint) - Amount to repay
- **Access**: Public
- **Returns**: `(response bool uint)`

### Liquidation

#### `liquidate-position(target-user)`
Liquidates an undercollateralized position.
- **Parameters**: `target-user` (principal) - Address of position to liquidate
- **Access**: Public
- **Returns**: `(response bool uint)`

### Read-Only Functions

#### `get-user-position(user-address)`
Retrieves user's lending position details.
- **Parameters**: `user-address` (principal)
- **Returns**: `(optional {...})`

#### `calculate-collateral-ratio(user-address)`
Calculates current collateral ratio for a position.
- **Parameters**: `user-address` (principal)
- **Returns**: `uint` (ratio as percentage)

#### `get-position-health-factor(user-address)`
Returns position health factor (100% = at liquidation threshold).
- **Parameters**: `user-address` (principal)
- **Returns**: `uint`

#### `is-liquidation-eligible(user-address)`
Checks if position is eligible for liquidation.
- **Parameters**: `user-address` (principal)
- **Returns**: `bool`

#### `get-protocol-metrics()`
Returns comprehensive protocol statistics.
- **Returns**: Protocol metrics object

#### `get-position-summary(user-address)`
Returns detailed position information.
- **Parameters**: `user-address` (principal)
- **Returns**: Position summary object

### Governance Functions

#### `update-asset-price(asset-symbol, price-usd-cents)`
Updates asset price in oracle (owner only).
- **Parameters**: 
  - `asset-symbol` (string-ascii 32)
  - `price-usd-cents` (uint)
- **Access**: Owner only
- **Returns**: `(response bool uint)`

#### `update-protocol-fee-rate(new-fee-rate)`
Updates protocol fee rate (owner only).
- **Parameters**: `new-fee-rate` (uint) - New fee rate (max 10%)
- **Access**: Owner only
- **Returns**: `(response bool uint)`

#### `transfer-ownership(new-owner)`
Transfers protocol ownership (owner only).
- **Parameters**: `new-owner` (principal)
- **Access**: Owner only
- **Returns**: `(response bool uint)`

## Usage Examples

### Creating a Position and Borrowing

```clarity
;; 1. Create a lending position
(contract-call? .dclp create-lending-position)

;; 2. Deposit 1000 STX as collateral
(contract-call? .dclp deposit-collateral u1000000000)

;; 3. Borrow 400 STX (assuming STX price allows this)
(contract-call? .dclp borrow-against-collateral u400000000)

;; 4. Check position health
(contract-call? .dclp get-position-health-factor tx-sender)
```

### Liquidating a Position

```clarity
;; Check if position is eligible for liquidation
(contract-call? .dclp is-liquidation-eligible 'SP1234...)

;; Liquidate the position
(contract-call? .dclp liquidate-position 'SP1234...)
```

### Monitoring Protocol Health

```clarity
;; Get overall protocol metrics
(contract-call? .dclp get-protocol-metrics)

;; Get detailed position information
(contract-call? .dclp get-position-summary 'SP1234...)
```

## Security Considerations

### Risk Factors

1. **Oracle Risk**: Price feeds must be accurate and timely
2. **Liquidation Risk**: Positions below 130% ratio face liquidation
3. **Smart Contract Risk**: Code vulnerabilities could affect funds
4. **Governance Risk**: Protocol owner has significant control

### Safety Measures

- Over-collateralization requirements
- Automatic liquidation system
- Fee caps and validation
- Overflow protection
- Access controls

### Best Practices

- Monitor position health regularly
- Maintain collateral ratios well above minimum
- Understand liquidation mechanics
- Keep track of fee accrual

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u1 | ERR-UNAUTHORIZED-ACCESS | Caller lacks required permissions |
| u2 | ERR-INSUFFICIENT-COLLATERAL | Not enough collateral for operation |
| u3 | ERR-INSUFFICIENT-PROTOCOL-LIQUIDITY | Protocol lacks funds for loan |
| u4 | ERR-COLLATERAL-RATIO-TOO-LOW | Operation would violate ratio requirements |
| u5 | ERR-POSITION-NOT-FOUND | User has no lending position |
| u6 | ERR-POSITION-ALREADY-EXISTS | User already has a position |
| u7 | ERR-INVALID-AMOUNT | Amount is invalid or causes overflow |
| u8 | ERR-LIQUIDATION-CONDITIONS-NOT-MET | Position not eligible for liquidation |
| u9 | ERR-FEE-EXCEEDS-MAXIMUM | Fee rate exceeds 10% limit |
| u10 | ERR-ZERO-AMOUNT-NOT-ALLOWED | Zero amounts not permitted |

## Deployment

### Prerequisites

- Stacks blockchain node
- Clarity CLI tools
- Sufficient STX for deployment

### Deployment Steps

1. **Compile Contract**
   ```bash
   clarinet check
   ```

2. **Deploy to Testnet**
   ```bash
   clarinet deploy --testnet
   ```

3. **Initialize Oracle**
   ```bash
   # Set initial STX price
   clarinet call update-asset-price "STX" u10000
   ```

4. **Verify Deployment**
   ```bash
   clarinet call get-protocol-metrics
   ```