# Security model

This project is unaudited. Do not use it to protect funds yet.

The core has no filesystem, socket, clock, scheduler, or ambient-randomness
dependency. This makes the same signing logic usable in a Unix process, a
MirageOS/Solo5 unikernel, or a confidential-computing enclave. It does not by
itself provide isolation, attestation, rollback protection, policy, or secure
key provisioning.

Secret scalar multiplication and ECDSA signing go through
`Mirage_crypto_ec.P256k1`. Public-key recovery uses
`Mirage_crypto_blockchain.Secp256k1` only after signing, on the public digest and
signature, to derive Ethereum's parity bit. The latter is a reference
implementation and is not used with the private key.

Signing requires a caller-provided 32-byte ECDSA nonce. It must be uniformly
generated, independent of both key and message, kept secret, and never reused.
Enclave deployments should fail closed when their entropy source is unhealthy.
A repeated or biased nonce can disclose the private key.

Decoders reject non-canonical RLP, out-of-range scalars, high-s signatures,
malformed access lists, unsupported typed envelopes, invalid EIP-4844 versioned
hashes, and empty EIP-7702 authorization lists. The private RLP decoder bounds
recursion and rejects non-canonical encodings. ABI and EIP-712 entry points
apply byte, depth, node, string, and collection budgets; raw-string JSON entry
points check size before parsing. See `LIMITS.md`. Application policy—allowed
chain IDs, destinations, selectors, amounts, fees, and authorization
targets—remains the caller's responsibility.

RPC responses are untrusted input. Typed decoders reject malformed quantities,
hashes, addresses, receipts, blocks, logs, IDs, and result/error ambiguity. A
successful HTTP or JSON-RPC response does not prove chain identity or finality;
applications should pin expected chain IDs and use `safe`/`finalized` or their
own confirmation policy. Subscription reconnects deliberately surface gaps as
`Need_resync` rather than pretending the new head extends the old chain.

Please report vulnerabilities privately to the maintainers listed in the opam
metadata. Include a reproducer when possible and do not open a public issue
until a fix is available.
