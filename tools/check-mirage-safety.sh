#!/bin/sh
set -eu

packages=evm-types,evm-abi,evm-eip712,evm-crypto,evm-transaction,evm-rpc,evm-rpc-cohttp,evm-rpc-mirage,evm
deps=$(opam exec -- dune describe external-lib-deps --only-packages="$packages" 2>&1)
if printf '%s\n' "$deps" | grep -E '(^|[[:space:]])(unix|lwt\.unix|async_unix)([[:space:]]|$)' >/dev/null; then
  printf '%s\n' "host-only dependency found in the install closure" >&2
  printf '%s\n' "$deps" >&2
  exit 1
fi
printf '%s\n' "Mirage safety check passed: no Unix runtime dependency in the core/Mirage closure"
