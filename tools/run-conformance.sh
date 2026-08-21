#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compose_file="$project_root/conformance/docker-compose.yml"

cleanup() {
  docker compose -f "$compose_file" down --volumes --remove-orphans
}
trap cleanup EXIT INT TERM

docker compose -f "$compose_file" up --detach --wait

wait_for_rpc() {
  name=$1
  endpoint=$2
  attempts=0
  until curl --fail --silent --show-error \
    --header 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
    "$endpoint" >/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 90 ]; then
      echo "$name RPC did not become ready at $endpoint" >&2
      docker compose -f "$compose_file" logs "$name" >&2
      exit 1
    fi
    sleep 1
  done
}

wait_for_rpc geth http://127.0.0.1:18545
wait_for_rpc reth http://127.0.0.1:28545

cd "$project_root"
opam exec -- dune exec conformance/rpc_conformance.exe -- \
  --name geth --endpoint http://127.0.0.1:18545
opam exec -- dune exec conformance/rpc_conformance.exe -- \
  --name reth --endpoint http://127.0.0.1:28545
