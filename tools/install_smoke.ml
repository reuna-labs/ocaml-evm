let fail message =
  Format.eprintf "install smoke test failed: %s@." message;
  exit 1

let () =
  let address =
    Evm.Types.Address.of_hex "0x0000000000000000000000000000000000000000"
  in
  match address with
  | Error error -> fail (Format.asprintf "%a" Evm.Types.pp_error error)
  | Ok address ->
      let rendered = Evm.Types.Address.to_hex address in
      if rendered <> "0x0000000000000000000000000000000000000000" then
        fail "installed address codec returned an unexpected value";
      print_endline "ocaml-evm staged install passed"
