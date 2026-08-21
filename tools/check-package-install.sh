#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

staging_root=$(mktemp -d /tmp/ocaml-evm-install.XXXXXX)
cleanup() {
  case "$staging_root" in
    /tmp/ocaml-evm-install.*) rm -rf -- "$staging_root" ;;
    *) printf '%s\n' "refusing to remove unexpected staging path" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

before="$staging_root/opam-before"
after="$staging_root/opam-after"
cksum ./*.opam >"$before"
opam exec -- dune build @install
cksum ./*.opam >"$after"
if ! cmp -s "$before" "$after"; then
  printf '%s\n' "generated opam files were stale; review and rerun the gate" >&2
  diff -u "$before" "$after" || true
  exit 1
fi

prefix="$staging_root/prefix"
opam exec -- dune install --prefix "$prefix"

packages="evm-types evm-abi evm-eip712 evm-crypto evm-transaction evm-rpc evm-rpc-cohttp evm-rpc-unix evm-rpc-mirage evm-rpc-websocket evm"
for package in $packages; do
  test -f "$prefix/lib/$package/META"
  test -f "$prefix/lib/$package/dune-package"
  test -f "$prefix/lib/$package/opam"
done

if [ -n "${OCAMLPATH:-}" ]; then
  smoke_path="$prefix/lib:$OCAMLPATH"
else
  smoke_path="$prefix/lib"
fi
cp tools/install_smoke.ml "$staging_root/install_smoke.ml"
OCAMLPATH="$smoke_path" opam exec -- ocamlfind ocamlopt \
  -linkpkg -package digestif.c,evm "$staging_root/install_smoke.ml" \
  -o "$staging_root/install-smoke"
"$staging_root/install-smoke"
