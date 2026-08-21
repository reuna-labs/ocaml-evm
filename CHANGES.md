## 0.2.0~alpha1 (unreleased)

- Add typed Ethereum JSON-RPC methods and response models.
- Add EIP-1193 provider and deterministic mock interfaces.
- Add Cohttp/Lwt, Unix, and MirageOS HTTP adapters without adding I/O to the
  core package closure.
- Add WebSocket subscription protocol, explicit reconnect driver, and bounded
  canonical-head/reorg tracking.
- Decode Solidity `Error(string)`, `Panic(uint256)`, and custom revert data.
- Add digest-pinned Geth/Reth conformance nodes and live typed-RPC coverage,
  including cross-client agreement for signed transaction types 0, 1, 2, and
  4.
- Add an HTTP fault proxy and automated transport tests for malformed,
  mismatched, conflicting, oversized, RPC-error, and HTTP-error responses.
- Add a single release-gate command with an optional Docker conformance stage.
- Add configurable ABI and EIP-712 byte, depth, node, string, and collection
  budgets, including raw-string JSON entry points that reject oversized input
  before parsing.
- Add pinned official EIP-155 and `ethereum/tests` transaction fixtures for
  valid legacy/EIP-2930/EIP-1559 and malformed typed envelopes.
- Add staged-install and clean-switch release checks, plus an explicit
  WebSocket backend decision covering CSPRNG injection and authenticated TLS.

## 0.1.0

First release: validated EVM types, Ethereum ABI, EIP-712 structured data,
recoverable secp256k1 signing, and legacy plus EIP-2718 transaction envelopes.
