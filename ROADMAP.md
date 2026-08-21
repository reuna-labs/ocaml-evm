# Roadmap

## 0.1 — offline signing core

- [x] Canonical hex quantities, EIP-55 addresses, uint256, hashes, and low-s
  signatures.
- [x] ABI codec facade, canonical type parser, selectors, tuple/array support,
  and contract ABI JSON descriptions.
- [x] EIP-712 JSON parsing, dependency ordering, domain separation, and
  recursive structured-data hashing.
- [x] Explicit-entropy secp256k1 signing, verification, recovery, and address
  derivation.
- [x] Strict legacy/EIP-155, EIP-2930, EIP-1559, EIP-4844, and EIP-7702
  transaction envelopes.
- [x] Official EIP-712 vector, types 0–4 signing round trips, randomized parser
  checks, and a Mirage dependency gate.
- [x] Move the underlying ABI implementation out of `web3-codec`.
- [x] Retain `web3-codec.Abi` as a documented deprecated forwarding
  compatibility layer for one release.
- [x] Add an independently sourced static transaction-vector corpus. Live
  differential submission now agrees with Geth and Reth for types 0, 1, 2,
  and 4.
- [x] Audit allocation limits for ABI and EIP-712 JSON before the first public
  release.

## 0.2 — transport adapters

- [x] Curated typed JSON-RPC methods for chain identity, blocks, calls, fee data,
  nonces, logs, receipts, transaction submission, and error decoding.
- [x] Separate Unix (`cohttp-lwt-unix`) and Mirage (`cohttp-mirage`) transports
  behind a small transport signature; no transport dependency in the core.
- [x] WebSocket subscriptions with explicit reconnection and reorg semantics.
- [x] EIP-1193-compatible provider adapter and deterministic mock transport.
- [ ] Add a maintained concrete WebSocket wire backend when one supports the
  current Cohttp/Conduit versions; the protocol driver is backend-neutral.
- [x] Select `httpun-ws` as the cross-runtime backend direction and document
  the required CSPRNG injection and authenticated TLS work before integration.
- [x] Add digest-pinned integration tests against Geth and Reth, including
  typed read methods, EIP-1898, signed transaction submission, receipts, and
  cross-client hash agreement.
- [x] Add bounded fault-injection coverage for malformed JSON, response-ID
  mismatch, JSON-RPC errors, conflicting result/error, HTTP failures, and
  oversized responses, plus a standalone HTTP proxy.
- [ ] Add WebSocket wire-level fault and reconnect tests once the maintained
  concrete backend is selected.

## 0.2 release gate

- [x] One command for formatting, build/install targets, all unit and fault
  tests, Mirage dependency closure, and opam lint.
- [x] Optional one-command Docker matrix with clean dev chains and pinned
  multi-architecture image digests.
- [x] Live signed transaction coverage for envelope types 0, 1, 2, and 4.
- [ ] Submit a valid type-3 network wrapper after the KZG/blob-sidecar package
  exists; the current matrix checks rejection of a bare type-3 payload.
- [x] Complete ABI/EIP-712 allocation audits and import independent static
  transaction fixtures before tagging `0.2.0-alpha`.
- [x] Verify generated package metadata and compile a consumer from a staged
  install prefix.
- [ ] Pass the automated clean-switch install on both OCaml 5.2 and the
  minimum supported OCaml 4.14 compiler.

## 0.3 — enclave and wallet integration

- Attested signer protocol with a transcript binding request, policy, chain ID,
  code measurement, and response.
- Anti-rollback counters and sealed-key lifecycle interfaces.
- EIP-191 personal-message helpers, encrypted keystore adapters, and hardware
  wallet integration.
- Reusable transaction-policy engine for chain, fee, destination, selector,
  calldata, and EIP-7702 authorization constraints.

## Later ecosystem projects

- KZG/blob sidecar package with a pluggable trusted-setup provider.
- Ethereum state proof, receipt, log-bloom, and MPT verification packages.
- SSZ and consensus light-client primitives, kept separate from execution-layer
  transaction code.
- ENS resolution, SIWE, ERC token helpers, account abstraction, and safe
  contract-binding generation from ABI JSON.
