let () =
  if Array.length Sys.argv <> 2 then (
    Format.eprintf "usage: %s RPC_URL@." Sys.argv.(0);
    exit 2);
  let client = Evm_rpc_unix.create (Uri.of_string Sys.argv.(1)) in
  match
    Lwt_main.run (Evm_rpc_unix.Client.call client Evm_rpc.Methods.chain_id)
  with
  | Ok chain_id -> Format.printf "%a@." Evm_types.Chain_id.pp chain_id
  | Error error ->
      Format.eprintf "%a@." Evm_rpc.Error.pp error;
      exit 1
