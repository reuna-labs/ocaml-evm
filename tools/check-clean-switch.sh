#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mirage_crypto_source=${MIRAGE_CRYPTO_SOURCE:-"$project_root/../ocaml/mirage-crypto"}
ocaml_package=${EVM_OCAML_PACKAGE:-ocaml-base-compiler.5.2.0}
switch_dir=$(mktemp -d /tmp/ocaml-evm-switch.XXXXXX)
rmdir "$switch_dir"

cleanup() {
  case "$switch_dir" in
    /tmp/ocaml-evm-switch.*)
      opam switch remove "$switch_dir" --yes >/dev/null 2>&1 || true
      ;;
    *) printf '%s\n' "refusing to remove unexpected switch path" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

test -f "$mirage_crypto_source/mirage-crypto-ec.opam"
test -f "$mirage_crypto_source/mirage-crypto-blockchain.opam"

opam switch create "$switch_dir" "$ocaml_package" --yes
for package in mirage-crypto mirage-crypto-rng mirage-crypto-ec \
  mirage-crypto-pk mirage-crypto-blockchain; do
  opam pin add --switch="$switch_dir" "$package.dev" \
    "$mirage_crypto_source" --no-action --yes
done
opam install --switch="$switch_dir" "$project_root" --deps-only --with-test \
  --yes
opam install --switch="$switch_dir" "$project_root" --with-test --yes
EVM_ENABLE_NETWORK_TESTS=1 opam exec --switch="$switch_dir" -- \
  dune runtest --root "$project_root" --force
printf '%s\n' "Clean-switch package install passed with $ocaml_package"
