let ok = function
  | Ok x -> x
  | Error _ -> failwith "invalid example constant"

let () =
  let open Evm in
  let private_key =
    Crypto.private_key_of_bytes (String.make 31 '\000' ^ "\001") |> ok
  in
  let transaction =
    Transaction.Dynamic_fee
      {
        chain_id = Types.Chain_id.of_int 1 |> ok;
        nonce = Types.Uint256.zero;
        max_priority_fee_per_gas = Types.Uint256.of_int 2_000_000_000 |> ok;
        max_fee_per_gas = Types.Uint256.of_int 30_000_000_000 |> ok;
        gas_limit = Types.Uint256.of_int 21_000 |> ok;
        to_ =
          Transaction.Call
            (Types.Address.of_hex "0x3535353535353535353535353535353535353535"
            |> ok);
        value = Types.Uint256.of_int 1 |> ok;
        data = "";
        access_list = [];
      }
  in
  let signed =
    Transaction.sign
      ~nonce:(String.make 31 '\000' ^ "\002")
      private_key
      transaction
    |> ok
  in
  let raw = Transaction.encode_signed signed |> ok in
  print_endline (Types.Hex.encode raw)
