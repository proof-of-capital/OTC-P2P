# OTC-P2P Protocol — Documentation

## What problem the protocol solves

Imagine a fund or an operator that needs to raise capital for upcoming deals. The classic problem: either people are asked to "transfer the money to us" — and then they have to trust the operator — or commitments are collected verbally, and then it is unclear whether the money is actually there.

OTC-P2P solves this differently. Each investor gets a personal on-chain vault that holds their funds. The money physically stays under the owner's control — neither the operator nor anyone else can take it. Yet it is visible on-chain as verifiable interest: the fund knows for sure that the capital is real and ready for a deal.

From there, the funds can be put to work — deliveries and swaps can be performed — but any movement of funds requires the owner's approval. And as trust grows, the client can gradually unlock progressively freer trading modes: from the strict "only an administrator's proposal is allowed" at the bottom, up to a full-fledged P2P market at the top.

In other words, this is not an exchange and not a wallet you have to trust. It is a set of rules enforced by a smart contract, where control always stays with the owner of the money, while the operator gets a tool to arrange deals and earn fees.

## What the protocol consists of

The system is built on three levels, designed for scale and security.

**Protocol Registry (`OTCFactoryRegistry`)** is the root of the whole system. It deploys factories for operators, stores the reference vault implementation (from which all client contracts are cloned), manages the protocol's share of fees, and maintains the registry of referral agents. This is where the protocol portion of fees flows.

**Operator Factory (`OTCOperatorFactory`)** is the "workspace" of a specific operator. Through it, the operator deploys vaults for their clients, sets their default fees, and configures default token locks. The factory has two roles: `owner` (the operator, strategic settings) and `admin` (the operational role that runs deals inside the vaults). One operator = one factory = a whole farm of many client vaults.

**Client vault** comes in two flavors:

| Contract | What it does |
|---|---|
| `OTCClientVault` | Full version: deliveries + swaps with four access levels |
| `OTCClientVaultLight` | Lightweight version: direct deliveries only, no swaps |

The vault `owner` is always the client. Vaults are deployed as lightweight clones (EIP-1167) from the reference implementation, so creating a new client is cheap.

## Protection against spoofing

Since the frontend could theoretically be spoofed, the protocol is designed so that the authenticity of a vault is verified at the contract level. When a factory registers a new vault in the registry, the registry performs three cross-checks: that the call came from a genuine factory, that the vault points to exactly this factory, and that the factory in turn recognizes this vault as its own. A "fake" contract cannot pass all three checks — so the client can always verify that their vault was created by the operator's real infrastructure.

## Who can do what (roles)

| Role | Contract | Capabilities |
|---|---|---|
| Protocol owner | Registry | Deploy factories, protocol fee share, agent registry, withdraw protocol fees |
| Operator (`owner`) | Factory | Deploy client vaults, configure own fees and locks, assign `admin` |
| Operator admin | Factory → Vault | Propose and approve deals inside client vaults |
| Client (`owner`) | Vault | Deposit/withdraw funds, approve deals, switch the trading mode |
| Counterparty | Vault | Approves its own side of a swap |

The core rule running through the entire codebase: the operator may propose, but any execution that moves the client's funds requires the client's approval. The only exception is actions that are unambiguously in the client's favor (for example, releasing locks early) — those the operator may perform alone.

## The four vault operating modes

The full version of the vault has a "switch" — `swapAccessLevel` — toggled only by the client. It defines how widely the vault is opened. The modes go from maximum protection to maximum freedom.

| Mode | What is allowed | Who initiates |
|---|---|---|
| **DeliveryOnly** (default) | Fund deliveries only. Swaps disabled | Operator proposes, client approves |
| **SupplierOnly** | Deliveries + "money ↔ asset" swaps at an agreed price | Operator proposes, client approves |
| **ManagedP2P** | Any participant can propose deals, but the operator approves each one | Participants, under operator control |
| **OpenP2P** | Free trading between participants without the operator | Any participants directly |

**DeliveryOnly** is the base and safest mode. The money sits in the vault; the operator can propose a delivery ("transfer N tokens to this address"), but the transfer happens only after the client agrees. This mode alone is enough to collect verifiable on-chain interest for future deals.

**SupplierOnly** adds swaps: the client gives away funds and receives an asset in return (for example, tokenized shares). The operator is still the initiator, and the approval logic stays the same.

**ManagedP2P** opens a market between participants, but under supervision: the operator acts as a censor and approves each deal (checking the counterparty's KYC, price fairness, etc.). This is their area of responsibility and source of fees.

**OpenP2P** is a fully free secondary market without the operator. An important safeguard: in this mode you can trade only with funds that are not locked. Anything reserved for a specific deal stays protected.

## Lock logic (freezing funds)

A lock exists so that, once a deal is agreed, the investor cannot "pull" liquidity at the last moment. It is designed to be fundamentally fair — always in the client's favor:

- **Setting or extending a lock** is only possible with the client's consent. The operator proposes a lock (`proposeLock`), and the client accepts it (`acceptLockProposal`). A lock cannot be imposed against the client's will.
- **Releasing or reducing a lock early** the operator can do alone (`adminDecreaseLock`) — because it is always in the client's favor, freeing their funds sooner.
- **A lock cannot be permanent**: the maximum duration is one year (`MAX_LOCK_DURATION = 365 days`).

While a token is locked, it cannot be withdrawn and cannot be used in free OpenP2P. But in operator-assisted modes, locked funds can be used in agreed deals — which is the whole point of a lock.

## Deliveries and swaps: how a deal flows

Any action with funds follows the "propose → approve → execute" model.

**Delivery.** A proposal is created specifying the token, amount, and recipient. Each party's approval is set automatically on creation or can be given separately. Execution requires the client's approval; in modes beyond the base one — also the operator's approval. Delivery supports two variants: a direct transfer to an address, or "allowance-and-call" — where the vault grants an allowance and calls an external contract (for example, to receive an asset back), with a check that at least the expected minimum was received.

**Swap.** Three parties are involved here: the client (gives `tokenOut`), the counterparty (gives `tokenIn`), and, depending on the mode, the operator. Execution requires approvals from all necessary parties. At execution, the contract pulls the counterparty's tokens and sends the client's tokens back in a single call — the deal is atomic and cannot get "stuck" halfway.

## Fees

Fees are set in basis points (10,000 = 100%) and are captured as a "snapshot" at the moment a proposal is created — meaning the terms of a deal cannot change retroactively while it is in progress.

The fairness principle is hard-coded:

- The operator can change their fees, but only for new vaults. For existing clients, terms never get worse.
- If a fee is reduced, the client can pull the new value to themselves (`syncFeeFromFactory`) — but the function only allows improvement, never deterioration.
- The protocol's share of the fee can also only decrease for already-running factories, never increase. And it cannot drop below a hard minimum.

Each fee is split into two parts: the protocol's share (goes to the registry) and the operator's share (goes to the operator's receiver). If a factory has an assigned referral agent, part of the protocol's share is reserved for them — the agent later claims it themselves.

## What auditors should pay attention to

A few places that deserve special attention.

**Arbitrary call in allowance-mode delivery.** In "allowance-and-call" mode, the vault executes `target.call(callData)` with parameters from the proposal. This is a powerful mechanism but also a point of trust: security here relies on the fact that the proposal passed the client's approval, that the vault zeroes out the allowance after the call, and that the minimum received amount is verified. This branch is worth reviewing especially carefully.

**Off-chain guarantees.** The protocol does not verify on-chain the fairness of a price, the counterparty's KYC, or the operator's good faith in ManagedP2P mode. These are organizational guarantees that live outside the contract — and should be flagged as trust assumptions.

**Separation of "propose" and "execute".** The key invariant worth confirming throughout the code: no path should move the client's funds without their approval, except for actions clearly in their favor (releasing locks, syncing fees downward).