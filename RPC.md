# Typed RPC and transport adapters

`evm-rpc` contains no scheduler, sockets, URI parser, or host runtime. A method
value carries its JSON-RPC name, parameters, and result decoder. The same value
can be executed by an EIP-1193 provider, deterministic mock, Unix HTTP client,
MirageOS client, or another adapter.

## Method catalog

The initial catalog includes client and network identity, chain ID, block
number, balances, account nonces, bytecode, `eth_call`, gas estimation, legacy
and priority fee data, EIP-1559/EIP-4844 fee history, blocks with transaction
hashes, logs, receipts, and signed transaction submission.

Block parameters distinguish EIP-1898 references from methods that only accept
a tag or quantity. Quantities, addresses, hashes, data, receipt status, and
nullable pending fields are decoded through validated EVM types. Full block
transaction objects, tracing, debugging, engine, and client-specific methods
are intentionally outside the curated surface; applications can construct an
additional `Method.t` without changing the transport.

## Provider boundary

`Evm_rpc.Provider.S` is the EIP-1193-shaped boundary: a method name and list of
JSON-compatible parameters produce either a JSON-compatible result or a
structured provider error in the provider's own effect type. `Provider.Make`
adds typed method decoding. `Mock.Provider` uses the identity effect and checks
the exact ordered sequence of expected calls.

HTTP transports use JSON-RPC 2.0 envelopes and check response IDs, HTTP status,
the `jsonrpc` marker, and result/error exclusivity. `evm-rpc-cohttp` contains the
shared Lwt implementation. `evm-rpc-unix` instantiates it with
`Cohttp_lwt_unix.Client`; `evm-rpc-mirage` is a functor over the Mirage resolver
and conduit modules and accepts an optional X.509 authenticator.

## Subscriptions and reorgs

`Evm_rpc.Subscription` encodes `eth_subscribe`/`eth_unsubscribe` and decodes
`newHeads` and log notifications. Its reconnect machine has explicit
Disconnected, Connecting, Subscribing, and Active states and increments a
generation after every disconnect.

`evm-rpc-websocket` drives this protocol over a small text-frame transport. A
wire backend supplies connect/send/receive/close; a closed connection yields
`Reconnect_required` instead of retrying invisibly. This lets Unix, Mirage,
browser, and test runtimes choose their own TLS, timeout, and backoff policy.

The head tracker keeps a bounded newest-first canonical history. Direct
extensions produce `Applied`; known-fork replacements produce `Reorg` with the
removed and added heads; an unknown parent produces `Need_resync`. The caller
must fetch a trusted range before resetting the tracker after a gap.

## Execution-client conformance

`conformance/rpc_conformance.ml` runs the typed Unix provider against clean,
digest-pinned Geth and Reth development chains. It checks read calls, block
models, EIP-1898 references, fee history, filters, local-versus-client
transaction hashes, and mined receipts for envelope types 0, 1, 2, and 4.

Type 3 has two wire forms: the execution payload represented by
`evm-transaction`, and the network wrapper carrying blobs, commitments, and
proofs. Until a KZG package owns the latter, the matrix asserts that clients
reject a bare type-3 payload rather than claiming valid blob submission.

The standalone HTTP fault proxy selects deterministic failures through the
`x-ocaml-evm-fault` header. Matching in-process tests cover the same failures
in the regular test suite. See `conformance/README.md` for commands and the
capability boundary.

## Trust and policy

Always verify `eth_chainId` against configuration. Treat RPC endpoints as
potentially Byzantine: they can omit logs, equivocate about heads, return stale
nonces, or censor submission. For high-assurance signers, independently verify
state proofs or require agreement between providers before policy decisions.
