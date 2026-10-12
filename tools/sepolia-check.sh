#!/usr/bin/env bash
# Public-testnet evidence for the published signing path: real Sepolia nodes
# judge bytes the released evm package produced.
#
#   tools/sepolia-check.sh
#
# Installs `evm` from the public Reuna opam overlay in a pinned container (a
# consumer's view, nothing from this checkout but examples/sepolia_sign.ml),
# signs an EIP-1559 transfer of 1 wei from a fresh key for Sepolia and the same
# transfer for chain 1, and submits both with eth_sendRawTransaction to each
# endpoint in SEPOLIA_RPCS.
#
# What a pass shows, per node:
#   - the Sepolia transaction reaches the balance check: "insufficient funds
#     ... want 1260000000000001", which is gas limit x max fee + value
#     (21000 x 60 gwei + 1 wei), so the type-2 envelope, every fee field and
#     the value decoded exactly as signed, and the signature recovered;
#   - the chain-1 transaction is refused as "invalid chain ID", so the node
#     checks the signed chain ID and ours is Sepolia's.
# What it does not show: that the node recovered the same sender this library
# derives. Any recoverable signature yields some unfunded address and the same
# error; proving the sender needs a funded key, so an accepted transaction
# returns this library's hash.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=docker.io/ocaml/opam:debian-12-ocaml-5.5@sha256:36803e379c31545ef00dfb64f8bdf3226b5e8c7b76746b636caedda811c625f3
OVERLAY=${EVM_OVERLAY:-https://github.com/reuna-labs/opam-repository.git}
SEPOLIA_RPCS=${SEPOLIA_RPCS:-"https://ethereum-sepolia-rpc.publicnode.com https://sepolia.drpc.org"}

echo "== the published evm, signing (overlay $OVERLAY)"
out=$(docker run --rm -e OVERLAY="$OVERLAY" -v "$here/examples/sepolia_sign.ml:/src/sepolia_sign.ml:ro" "$IMAGE" sh -ec '
	opam repository add reuna "$OVERLAY" >/dev/null 2>&1
	opam install -y --confirm-level=unsafe-yes evm >/tmp/install.log 2>&1 || { tail -20 /tmp/install.log >&2; exit 1; }
	opam list --installed --columns=name,version evm evm-transaction evm-crypto 2>/dev/null | grep -v "^#" >&2
	mkdir -p /tmp/w && cd /tmp/w && cp /src/sepolia_sign.ml .
	printf "(lang dune 3.0)\n" > dune-project
	printf "(executable (name sepolia_sign) (libraries evm))\n" > dune
	opam exec -- dune build ./sepolia_sign.exe >&2
	./_build/default/sepolia_sign.exe')
printf '%s\n' "$out" | sed 's/^/  /'

raw() { printf '%s\n' "$out" | awk -v c="$1" '$1=="chain" {f=($2==c)} f && $1=="raw" {print $2; exit}'; }
sepolia=$(raw 11155111)
mainnet=$(raw 1)
[ -n "$sepolia" ] && [ -n "$mainnet" ] || { echo "FAIL: the signer printed no transactions"; exit 1; }

send() { # send <rpc> <raw>: the node's error message, or its result
	curl -fsS -m 30 -H 'Content-Type: application/json' \
		-d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_sendRawTransaction\",\"params\":[\"$2\"]}" "$1" \
		| python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("error",{}).get("message") or d.get("result"))'
}
version() {
	curl -fsS -m 30 -H 'Content-Type: application/json' \
		-d '{"jsonrpc":"2.0","id":1,"method":"web3_clientVersion","params":[]}' "$1" \
		| python3 -c 'import json,sys; print(json.load(sys.stdin).get("result"))'
}

fail=0
for rpc in $SEPOLIA_RPCS; do
	echo "== $rpc ($(version "$rpc"))"
	got=$(send "$rpc" "$sepolia")
	case "$got" in
	*"insufficient funds"*"want 1260000000000001"*) echo "  ok: Sepolia transaction decoded to the balance check: $got" ;;
	*) echo "  FAIL: Sepolia transaction: $got"; fail=1 ;;
	esac
	got=$(send "$rpc" "$mainnet")
	case "$got" in
	*"invalid chain ID"*) echo "  ok: chain-1 transaction refused: $got" ;;
	*) echo "  FAIL: chain-1 transaction: $got"; fail=1 ;;
	esac
done

[ "$fail" = 0 ] && echo PASS || { echo FAIL; exit 1; }
