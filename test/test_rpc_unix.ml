let test_create () =
  let expected = Uri.of_string "https://rpc.example.invalid/v1" in
  let client = Evm_rpc_unix.create expected in
  Alcotest.(check string)
    "URI retained"
    (Uri.to_string expected)
    (Evm_rpc_unix.uri client |> Uri.to_string)

let test_limit () =
  Alcotest.check_raises
    "non-positive limit"
    (Invalid_argument "max_response_bytes must be positive")
    (fun () ->
      ignore
        (Evm_rpc_unix.create
           ~max_response_bytes:0
           (Uri.of_string "http://localhost")))

let () =
  Alcotest.run
    "ocaml-evm-rpc-unix"
    [
      ( "adapter",
        [
          Alcotest.test_case "create" `Quick test_create;
          Alcotest.test_case "response limit" `Quick test_limit;
        ] );
    ]
