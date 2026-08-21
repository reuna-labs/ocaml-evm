# WebSocket backend decision

`evm-rpc-websocket` deliberately contains only the subscription/reconnect
protocol driver. A concrete wire adapter is not part of `0.2.0~alpha1`.

## Candidate assessment

The established `websocket-lwt-unix` 2.17 package requires
`cohttp-lwt-unix < 6.0.0`, while `evm-rpc-unix` targets Cohttp 6.1 or newer.
Those packages cannot form one supported installation without downgrading the
HTTP adapter.

The selected direction is the `httpun-ws` family because it separates its
protocol core from Lwt/Unix, Eio, and Mirage runtimes. Before ocaml-evm ships an
adapter, two upstream-facing requirements must be resolved:

1. Client frame masking must accept a caller-supplied cryptographically secure
   random source. Version 0.2.0 currently uses `Random.int32` internally and
   marks the missing injection point as a TODO. MirageOS and enclave callers
   need to supply their platform CSPRNG explicitly.
2. The Unix adapter must support `wss://` with authenticated TLS, and the
   Mirage adapter must accept an already authenticated flow without adding
   Unix dependencies.

The eventual package split should be:

- `evm-rpc-websocket-httpun`: frame/message assembly and the existing driver
  bridge, with no Unix dependency;
- `evm-rpc-websocket-unix`: DNS, TCP, TLS, and Unix entropy;
- `evm-rpc-websocket-mirage`: functor over an authenticated Mirage flow and an
  explicit entropy source.

## Required wire tests

An adapter is not complete until local wire tests cover fragmented text
messages, interleaved ping/pong, binary-frame rejection, close frames,
handshake failure, invalid UTF-8/JSON, oversized assembled messages, response
ID mismatch, disconnect during subscribe, and resubscription after reconnect.
TLS tests must include hostname verification failure.

