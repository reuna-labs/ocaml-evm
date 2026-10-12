(* Signs one EIP-1559 transfer for Sepolia (chain 11155111) with a fresh key,
   and prints what a node needs to judge it: the sender this library derives,
   the transaction hash it computes, and the raw bytes. The key is new, so a
   node that decodes the bytes, checks the chain and recovers the sender
   answers "insufficient funds", and its own view of the sender and hash can
   be compared with these. *)
let ok what = function
  | Ok x -> x
  | Error _ -> failwith what

let urandom n =
  In_channel.with_open_bin "/dev/urandom" (fun ic -> really_input_string ic n)

let sign_for chain =
  let open Evm in
  let key = Crypto.private_key_of_bytes (urandom 32) |> ok "key" in
  let sender = Crypto.address (Crypto.public_key key) in
  let tx =
    Transaction.Dynamic_fee
      {
        chain_id = Types.Chain_id.of_int chain |> ok "chain";
        nonce = Types.Uint256.zero;
        max_priority_fee_per_gas =
          Types.Uint256.of_int 2_000_000_000 |> ok "tip";
        max_fee_per_gas = Types.Uint256.of_int 60_000_000_000 |> ok "fee";
        gas_limit = Types.Uint256.of_int 21_000 |> ok "gas";
        to_ =
          Transaction.Call
            (Types.Address.of_hex "0x000000000000000000000000000000000000dEaD"
            |> ok "to");
        value = Types.Uint256.of_int 1 |> ok "value";
        data = "";
        access_list = [];
      }
  in
  let signed = Transaction.sign ~nonce:(urandom 32) key tx |> ok "sign" in
  let recovered = Transaction.sender signed |> ok "sender" in
  let hash = Transaction.hash signed |> ok "hash" in
  let raw = Transaction.encode_signed signed |> ok "encode" in
  Printf.printf
    "chain %d\nsender %s\nrecovered %s\nhash %s\nraw %s\n"
    chain
    (Types.Address.to_hex sender)
    (Types.Address.to_hex recovered)
    (Types.Hash.to_hex hash)
    (Types.Hex.encode raw)

(* Sepolia, and the same transfer for chain 1, which a Sepolia node must
   refuse for its chain ID rather than for funds. *)
let () =
  sign_for 11155111;
  sign_for 1
