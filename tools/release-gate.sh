#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

opam exec -- dune fmt
opam exec -- dune build @all @install
EVM_ENABLE_NETWORK_TESTS=1 opam exec -- dune runtest --force
./tools/check-mirage-safety.sh
./tools/check-package-install.sh
opam lint ./*.opam

if [ "${EVM_RUN_CONFORMANCE:-0}" = "1" ]; then
  ./tools/run-conformance.sh
else
  echo "Skipping Docker conformance matrix (set EVM_RUN_CONFORMANCE=1 to run)."
fi
