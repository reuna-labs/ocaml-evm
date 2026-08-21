# ocaml-evm

Pure OCaml primitives for Ethereum and EVM-compatible chains, designed to run
unchanged in ordinary Unix programs and MirageOS/Solo5 unikernels.

The first release contains validated wire types, the Ethereum Contract ABI,
EIP-712 structured-data hashing, recoverable secp256k1 signatures, and legacy
plus typed transaction envelopes through EIP-7702. The core performs no I/O
and never reaches ambient randomness.

Status: `0.2.0~alpha1` candidate, under development and unaudited. Do not use
it to control funds yet.

## Packages

- `evm-types`: addresses, hashes, uint256 values and Ethereum hex encodings.
- `evm-abi`: ABI values, type strings, calls, events, errors and JSON ABIs.
- `evm-eip712`: `eth_signTypedData_v4` parsing and hashing.
- `evm-crypto`: a Mirage-crypto-backed recoverable secp256k1 interface.
- `evm-transaction`: strict legacy and EIP-2718 transaction envelopes.
- `evm-rpc`: typed JSON-RPC, EIP-1193 provider boundary, mock, revert decoding,
  and subscription/reorg state machines.
- `evm-rpc-cohttp`: shared Cohttp/Lwt HTTP implementation.
- `evm-rpc-unix`: Unix HTTP client using `cohttp-lwt-unix`.
- `evm-rpc-mirage`: MirageOS HTTP functor using `cohttp-mirage`.
- `evm-rpc-websocket`: backend-neutral WebSocket subscription driver.
- `evm`: an umbrella library re-exporting the package family.

## Design rules

- Parsers return `result` and reject non-canonical input.
- Signed and unsigned transactions are different types.
- Secret-key operations go through one cryptographic backend.
- No `Unix`, scheduler, sockets, filesystem or global RNG below adapters.
- Transport frames, RLP nesting, ABI decoding, ABI JSON, and EIP-712 JSON have
  explicit default allocation budgets and configurable stricter limits.

## Build and test

The project currently targets OCaml 4.14 or newer. It uses the secp256k1 and
blockchain packages from the local Mirage-crypto worktree; until those APIs are
released, pin the five exact-version packages in that dependency closure:

```sh
opam pin add mirage-crypto.dev ../ocaml/mirage-crypto
opam pin add mirage-crypto-rng.dev ../ocaml/mirage-crypto
opam pin add mirage-crypto-ec.dev ../ocaml/mirage-crypto
opam pin add mirage-crypto-pk.dev ../ocaml/mirage-crypto
opam pin add mirage-crypto-blockchain.dev ../ocaml/mirage-crypto
opam install . --deps-only --with-test
dune runtest
./tools/check-mirage-safety.sh
```

The release-hardening gate runs formatting, builds, unit/fault tests, Mirage
dependency checks, and opam linting:

```sh
./tools/release-gate.sh
```

Set `EVM_RUN_CONFORMANCE=1` to additionally start digest-pinned Geth and Reth
development nodes and run the live cross-client matrix. This requires Docker:

```sh
EVM_RUN_CONFORMANCE=1 ./tools/release-gate.sh
```

`Evm.Crypto.sign_digest` deliberately requires a fresh 32-byte nonce supplied
by the caller. An enclave or unikernel adapter should obtain it from its own
trusted RNG and must never reuse it. See [SECURITY.md](SECURITY.md).

Applications accepting untrusted ABI or typed-data JSON should use the bounded
raw-string entry points so the byte limit is checked before Yojson allocates a
tree. Defaults and customization points are documented in
[LIMITS.md](LIMITS.md).

## Scope

Version 0.1 is the offline signing core. It accepts EIP-4844 versioned hashes,
but intentionally does not implement KZG commitments, blobs, or sidecars. RPC,
ENS, wallet keystores, hardware-signing transports, and chain-specific policy
belong in adapters or later packages.

Version 0.2 adds transport-separated RPC. A Unix client can query a chain ID
without exposing Unix dependencies to the core or Mirage packages:

```ocaml
let client = Evm_rpc_unix.create (Uri.of_string endpoint) in
match Lwt_main.run (Evm_rpc_unix.Client.call client Evm_rpc.Methods.chain_id) with
| Ok chain_id -> Format.printf "%a@." Evm_types.Chain_id.pp chain_id
| Error error -> Format.eprintf "%a@." Evm_rpc.Error.pp error
```

The typed method catalog and subscription semantics are described in
[RPC.md](RPC.md). The execution-client matrix is described in
[conformance/README.md](conformance/README.md), and future milestones are
tracked in [ROADMAP.md](ROADMAP.md).

Release gates and versioning are documented in [RELEASING.md](RELEASING.md).
The concrete WebSocket backend assessment and its entropy/TLS requirements are
documented in [WEBSOCKETS.md](WEBSOCKETS.md).
