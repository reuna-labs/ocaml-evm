# Releasing ocaml-evm

The first public transport preview is `0.2.0~alpha1`, tagged as
`v0.2.0-alpha1`. Opam's `~alpha1` spelling sorts before the final `0.2.0`
release; the Git tag uses the more familiar hyphenated spelling.

## Release invariants

- All generated opam files contain the version from `dune-project`.
- A staged install contains every public package and can compile and execute a
  consumer outside the source tree.
- Fresh OCaml 5.2 and 4.14 switches can solve, build, test, and install the
  package set.
- The core and Mirage package closure contains no Unix runtime dependency.
- The unit, fault-injection, and digest-pinned Geth/Reth matrices pass.
- The source tree contains no uncommitted generated metadata.

The secp256k1 and blockchain APIs currently come from the adjacent
Mirage-crypto worktree. The clean-switch check pins its core, RNG, EC, PK, and
blockchain packages to one explicit `dev` version so their exact-version
constraints remain coherent. This is the only non-opam-repository input
accepted by the check. It must be replaced by released package constraints
before a final `0.2.0` release.

## Local gate

Run the deterministic checks and a staged consumer build:

```sh
./tools/release-gate.sh
```

Run the execution-client matrix before an alpha tag:

```sh
EVM_RUN_CONFORMANCE=1 ./tools/release-gate.sh
```

`tools/check-package-install.sh` installs all public libraries below a fresh
temporary prefix, verifies their metadata, and compiles a smoke-test consumer
against only that prefix plus the active switch's third-party dependencies.
The direct `ocamlfind` invocation selects `digestif.c` before `evm` so the
virtual implementation is linked in dependency order; Dune consumers select
Digestif's default implementation automatically.

The localhost fault-injection test is disabled during opam's sandboxed
`@runtest` phase because that sandbox forbids `bind(2)`. Both release scripts
run it explicitly afterward with `EVM_ENABLE_NETWORK_TESTS=1`; it is therefore
still mandatory for a passing release gate.

## Clean-switch gate

The following command creates an isolated external switch in `/tmp`, pins only
the required Mirage-crypto package closure, installs this repository with test
dependencies, runs the tests, and removes the switch on exit:

```sh
./tools/check-clean-switch.sh
```

Set `EVM_OCAML_PACKAGE=ocaml-base-compiler.4.14.2` to exercise the minimum
supported compiler. Set `MIRAGE_CRYPTO_SOURCE` if the worktree is not at
`../ocaml/mirage-crypto`.

## Tagging and publishing

Tagging and pushing are intentionally separate from the automated checks:

1. Change the changelog heading from `unreleased` to the release date.
2. Run both gates above, including Docker conformance.
3. Confirm `git status --short` is empty.
4. Create the annotated tag `v0.2.0-alpha1`.
5. Publish the tag and submit the generated opam files only after reviewing
   their dependency constraints.
