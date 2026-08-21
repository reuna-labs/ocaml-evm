# Contributing

Run the complete local checks before submitting changes:

```sh
dune build @all
dune runtest
dune fmt
./tools/check-mirage-safety.sh
```

`./tools/release-gate.sh` runs the complete local gate. Before a release or a
change to transactions/RPC transports, also run the digest-pinned execution
client matrix:

```sh
EVM_RUN_CONFORMANCE=1 ./tools/release-gate.sh
```

Release candidates must also pass `./tools/check-clean-switch.sh`; see
[RELEASING.md](RELEASING.md) for compiler selection and the temporary-switch
lifecycle.

The HTTP fault test binds an ephemeral localhost port and is enabled by the
release scripts with `EVM_ENABLE_NETWORK_TESTS=1`. Set the same variable when
running that test directly; opam package builds leave it disabled because
their build sandbox denies socket binding.

The matrix downloads Geth and Reth images, binds localhost ports 18545 and
28545, and removes its containers and named volumes on exit. Its fixture keys
are public development keys and must never be reused on a real chain.

New wire formats need positive vectors, malformed/non-canonical regression
cases, round-trip properties, and a decoder-totality fuzz property. Cryptographic
changes also need cross-implementation vectors and a note explaining whether
secret-dependent data reaches the changed code.

Keep core libraries free of `Unix`, Lwt schedulers, network clients, files,
clocks, and global randomness. Put host- or runtime-specific behavior in an
adapter package.
