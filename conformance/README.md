# Execution-client conformance

This directory runs the same typed `evm-rpc-unix` client against pinned Geth
and Reth development nodes. Both nodes use chain ID 1337 and the public,
well-known test key from the `test test ... junk` development mnemonic. Never
use the fixture key outside disposable test chains.

Run the matrix from the repository root:

```sh
./tools/run-conformance.sh
```

The harness covers client/network identity, quantities, blocks by number and
hash, EIP-1898 block references, balances, nonces, code, calls, gas estimation,
fee history, filters, receipts, and signed transaction types 0, 1, 2, and 4.
For type 3 it verifies that a bare execution payload is rejected: submitting a
valid blob transaction also requires the network wrapper with blobs,
commitments, and proofs, which is deliberately outside `evm-transaction` until
the KZG package exists.

`fault_proxy.exe` is a manual fault-injecting HTTP proxy. Select a fault with
the `x-ocaml-evm-fault` header: `malformed`, `id-mismatch`, `rpc-error`,
`conflicting`, `oversized`, or `http-500`. The same cases run automatically in
`test/test_rpc_faults.ml` without needing Docker.

```sh
dune exec conformance/fault_proxy.exe -- \
  --upstream http://127.0.0.1:18545 --listen 38545
```

The Compose services use named volumes. The runner removes containers and
volumes on exit so every matrix begins from genesis.
