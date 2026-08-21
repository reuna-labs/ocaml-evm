(lang dune 3.6)

(name evm)

(version 0.2.0~alpha1)

(generate_opam_files true)

(implicit_transitive_deps false)

(source
 (github reuna-labs/ocaml-evm))

(license ISC)

(authors "Gil Bahat <bahat.gil@gmail.com>")

(maintainers "Gil Bahat <bahat.gil@gmail.com>")

(package
 (name evm-types)
 (synopsis "Validated primitive types for Ethereum and EVM chains")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (zarith (>= 1.13))
  (digestif (>= 1.2.0))))

(package
 (name evm-abi)
 (synopsis "Ethereum Contract ABI encoding, decoding and descriptions")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (evm-types (= :version))
  (zarith (>= 1.13))
  (digestif (>= 1.2.0))
  (yojson (>= 2.0.0))))

(package
 (name evm-eip712)
 (synopsis "EIP-712 structured-data parsing and hashing")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (evm-types (= :version))
  (evm-abi (= :version))
  (zarith (>= 1.13))
  (digestif (>= 1.2.0))
  (yojson (>= 2.0.0))))

(package
 (name evm-crypto)
 (synopsis "Cryptographic backend interface for EVM signing")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (evm-types (= :version))
  (zarith (>= 1.13))
  (digestif (>= 1.2.0))
  mirage-crypto-ec
  mirage-crypto-blockchain))

(package
 (name evm-transaction)
 (synopsis "Legacy and typed Ethereum transaction envelopes")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (evm-types (= :version))
  (evm-crypto (= :version))
  (zarith (>= 1.13))))

(package
 (name evm-rpc)
 (synopsis "Typed, transport-independent Ethereum JSON-RPC client")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (evm-types (= :version))
  (evm-abi (= :version))
  (evm-transaction (= :version))
  (zarith (>= 1.13))
  (yojson (>= 2.0.0))
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test)))

(package
 (name evm-rpc-cohttp)
 (synopsis "Cohttp/Lwt transport shared by EVM RPC runtime adapters")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (evm-rpc (= :version))
  (lwt (>= 5.6.0))
  (uri (>= 4.2.0))
  (http (>= 6.1.0))
  (cohttp-lwt (>= 6.1.0))))

(package
 (name evm-rpc-unix)
 (synopsis "Unix HTTP transport for evm-rpc")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (evm-rpc-cohttp (= :version))
  (cohttp-lwt-unix (>= 6.1.0))
  (alcotest :with-test)))

(package
 (name evm-rpc-mirage)
 (synopsis "MirageOS HTTP transport for evm-rpc")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (evm-rpc-cohttp (= :version))
  (cohttp-mirage (>= 6.1.0))
  (conduit-mirage (>= 8.0.0))
  x509
  lwt
  uri
  http
  cohttp-lwt))

(package
 (name evm-rpc-websocket)
 (synopsis "Backend-neutral WebSocket subscription driver for evm-rpc")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (evm-rpc (= :version))
  (yojson (>= 2.0.0))
  (alcotest :with-test)))

(package
 (name evm)
 (synopsis "Pure OCaml SDK for Ethereum and EVM-compatible chains")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (evm-types (= :version))
  (evm-abi (= :version))
  (evm-eip712 (= :version))
  (evm-crypto (= :version))
  (evm-transaction (= :version))
  (evm-rpc (= :version))
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test)))
