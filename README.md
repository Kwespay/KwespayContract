
# KwesPay Contracts

On-chain payment settlement with strict verification and instant execution.

Customers pay. The contract verifies. Funds are split in one transaction.
No custody. No escrow. No intermediaries.

---

## Architecture

All payments are pre-signed off-chain and strictly verified on-chain, preventing unauthorized execution and replay.

<p align="center">
  <img src="https://arthuremma2.github.io/img-hosting/arch.svg" alt="KwesPay Payment Flow" width="720"/>
</p>

---

## How It Works

1. Backend signs a payment payload
2. Customer calls `createPayment()`
3. Contract verifies all conditions
4. Funds are split instantly

Any failed check reverts the transaction.

---

## Core Guarantees

**Authorized execution only**
Every payment must include a valid backend signature.

**Replay protection**
Each `paymentId` can only be used once.

**Strict validation**

* signature must be valid
* deadline must not be expired
* vendor must be active
* token must be approved

**Atomic settlement**

* vendor receives full amount
* fee is extracted
* executed in a single transaction

**No custody**
Funds never sit in the contract.

---

## Contracts

| Contract       | Description           |
| -------------- | --------------------- |
| `Payment.sol`  | Core settlement logic |
| `MockUSDT.sol` | Testnet ERC-20        |

---

## Fee Model

Customer pays:

```
amount + fee
```

* vendor receives `amount`
* platform receives `fee`

---

## Setup

```bash
pnpm install
npx hardhat compile
```

```env
PRIVATE_KEY=0x...
MEZO_TESTNET_RPC_URL=...
LISK_TESTNET_RPC_URL=...
ETHERSCAN_API_KEY=...
```

---

## Deploy

```bash
npx hardhat run scripts/deploy.js --network mezoTestnet
```

---

## Design Principles

* No intermediaries
* No delayed settlement
* Deterministic execution
* Fail fast on invalid input

---

## License

MIT

