# Parser and allocation limits

ABI and EIP-712 inputs commonly cross an RPC, wallet, or enclave trust
boundary. Their default entry points therefore apply conservative structural
budgets. Every bounded API also has a `*_with_limits` variant whose record must
be supplied explicitly when an application needs a different policy.

## ABI defaults

| Budget | Default |
| --- | ---: |
| Encoded ABI or raw ABI-JSON input | 16 MiB |
| One decoded dynamic byte/string value | 1 MiB |
| Type/tuple/array nesting | 64 |
| Elements in one tuple or array | 4,096 |
| Items in one contract ABI | 4,096 |
| Type, parameter, and item-name string | 4 KiB |

`decode_with_limits` validates the complete declared type shape before reading
the byte buffer. It rejects layouts whose minimum static size cannot fit the
input budget, so nested fixed arrays cannot overflow OCaml integer arithmetic
before the actual decode begins.

For an untrusted JSON string, prefer `contract_of_json_string` or
`contract_of_json_string_with_limits`. These check the raw byte count before
calling Yojson. `contract_of_yojson` can only bound traversal and secondary
allocations because the caller has already constructed the JSON tree.

## EIP-712 defaults

| Budget | Default |
| --- | ---: |
| Raw typed-data JSON input | 4 MiB |
| JSON nesting | 64 |
| JSON nodes | 100,000 |
| Elements in one JSON array | 4,096 |
| Fields in one JSON object | 4,096 |
| One JSON string | 1 MiB |
| Named struct types | 256 |
| Members in one struct type | 256 |
| Type/member identifier | 256 bytes |

`of_json_string` checks the raw input before parsing and then validates the
entire JSON tree. `digest` revalidates the public `t` record before hashing, so
manually constructed values do not bypass the defaults. Use
`digest_with_limits` to enforce a stricter enclave or application policy.

The budgets limit work performed by `ocaml-evm`; they do not impose a timeout
or a process-wide memory limit. Callers should still bound transport frames,
concurrent requests, and execution time at their own trust boundary.
