open Lwt.Syntax

let failf fmt = Printf.ksprintf failwith fmt

let or_fail label pp_error = function
  | Ok value -> value
  | Error error -> failf "%s: %s" label (Format.asprintf "%a" pp_error error)

let evm_type label value = or_fail label Evm_types.pp_error value

let result label = function
  | Ok value -> value
  | Error error -> failf "%s: %s" label error

let uint n = evm_type "uint256" (Evm_types.Uint256.of_int n)
let uint_z n = evm_type "uint256" (Evm_types.Uint256.of_z n)
let address value = evm_type "address" (Evm_types.Address.of_hex value)

let key value =
  let raw = evm_type "private key hex" (Evm_types.Hex.decode ("0x" ^ value)) in
  or_fail
    "private key"
    Evm_crypto.pp_error
    (Evm_crypto.private_key_of_bytes raw)

let sender_key =
  key "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

let authority_key =
  key "59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

let sender = Evm_crypto.address (Evm_crypto.public_key sender_key)
let authority = Evm_crypto.address (Evm_crypto.public_key authority_key)
let recipient = address "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc"
let delegate = address "0x90f79bf6eb2c4f870365e785982e1f101e93b906"

let rpc client label method_ =
  let* response = Evm_rpc_unix.Client.call client method_ in
  match response with
  | Ok value -> Lwt.return value
  | Error error ->
      failf "%s: %s" label (Format.asprintf "%a" Evm_rpc.Error.pp error)

let add_uint value increment =
  Evm_types.Uint256.to_z value |> fun value ->
  uint_z Z.(value + of_int increment)

let wait_for_receipt client hash =
  let rec loop attempts =
    if attempts = 0 then
      failf "timed out waiting for receipt %s" (Evm_types.Hash.to_hex hash)
    else
      let* receipt =
        rpc
          client
          "eth_getTransactionReceipt"
          (Evm_rpc.Methods.transaction_receipt hash)
      in
      match receipt with
      | Some receipt -> Lwt.return receipt
      | None ->
          let* () = Lwt_unix.sleep 0.5 in
          loop (attempts - 1)
  in
  loop 60

let wait_for_latest_block client =
  let rec loop attempts =
    if attempts = 0 then failwith "timed out waiting for the first block"
    else
      let* block =
        rpc
          client
          "eth_getBlockByNumber"
          (Evm_rpc.Methods.block_by_number (`Tag Latest))
      in
      match block with
      | Some ({ hash = Some _; _ } as block) -> Lwt.return block
      | None | Some _ ->
          let* () = Lwt_unix.sleep 0.5 in
          loop (attempts - 1)
  in
  loop 60

let sign_tx transaction signature_nonce =
  let entropy =
    String.make 31 '\000' ^ String.make 1 (Char.chr signature_nonce)
  in
  result
    "sign transaction"
    (Evm_transaction.sign ~nonce:entropy sender_key transaction)

let submit client ~expected_type signed =
  let expected_hash =
    result "local transaction hash" (Evm_transaction.hash signed)
  in
  let method_ =
    result
      "encode raw transaction"
      (Evm_rpc.Methods.send_raw_transaction signed)
  in
  let* actual_hash = rpc client "eth_sendRawTransaction" method_ in
  if not (Evm_types.Hash.equal expected_hash actual_hash) then
    failf
      "client transaction hash %s differs from local hash %s"
      (Evm_types.Hash.to_hex actual_hash)
      (Evm_types.Hash.to_hex expected_hash);
  let* receipt = wait_for_receipt client actual_hash in
  if not (Evm_types.Hash.equal receipt.transaction_hash actual_hash) then
    failwith "receipt transaction hash mismatch";
  (match receipt.status with
  | Some true -> ()
  | _ -> failf "transaction type %d did not succeed" expected_type);
  (match receipt.type_ with
  | None when expected_type = 0 -> ()
  | Some value
    when Z.equal (Evm_types.Uint256.to_z value) (Z.of_int expected_type) -> ()
  | _ ->
      failf "receipt reported the wrong transaction type for %d" expected_type);
  Printf.printf
    "  ok transaction type %d %s\n%!"
    expected_type
    (Evm_types.Hash.to_hex actual_hash);
  Lwt.return_unit

let malformed_envelope client type_byte =
  let raw = Printf.sprintf "0x%02xc0" type_byte in
  let method_ =
    Evm_rpc.Method.make
      ~name:"eth_sendRawTransaction"
      ~params:[ `String raw ]
      (fun _ -> Ok ())
  in
  let* response = Evm_rpc_unix.Client.call client method_ in
  match response with
  | Error (Evm_rpc.Error.Rpc _) ->
      Printf.printf "  ok malformed type %d rejected\n%!" type_byte;
      Lwt.return_unit
  | Error error ->
      failf
        "malformed type %d returned a non-RPC error: %s"
        type_byte
        (Format.asprintf "%a" Evm_rpc.Error.pp error)
  | Ok () -> failf "malformed type %d was accepted" type_byte

let transaction_set chain_id first_nonce authority_nonce =
  let open Evm_transaction in
  let gas_price = uint 2_000_000_000 in
  let priority = uint 1_000_000_000 in
  let max_fee = uint 3_000_000_000 in
  let transfer nonce = (Call recipient, uint 1, nonce, uint 21_000, "", []) in
  let to_, value, nonce0, gas_limit, data, access_list = transfer first_nonce in
  let nonce1 = add_uint first_nonce 1 in
  let nonce2 = add_uint first_nonce 2 in
  let nonce4 = add_uint first_nonce 3 in
  let authorization_hash =
    authorization_signing_hash
      ~chain_id:(uint_z (Evm_types.Chain_id.to_z chain_id))
      ~address:delegate
      ~nonce:authority_nonce
  in
  let authorization_signature =
    let entropy = String.make 31 '\000' ^ "\x55" in
    or_fail
      "sign EIP-7702 authorization"
      Evm_crypto.pp_error
      (Evm_crypto.sign_digest ~nonce:entropy authority_key authorization_hash)
  in
  let authorization =
    {
      chain_id = uint_z (Evm_types.Chain_id.to_z chain_id);
      address = delegate;
      nonce = authority_nonce;
      signature = authorization_signature;
    }
  in
  [
    ( 0,
      sign_tx
        (Legacy
           {
             nonce = nonce0;
             gas_price;
             gas_limit;
             to_;
             value;
             data;
             chain_id = Some chain_id;
           })
        0x31 );
    ( 1,
      sign_tx
        (Access_list
           {
             chain_id;
             nonce = nonce1;
             gas_price;
             gas_limit;
             to_;
             value;
             data;
             access_list;
           })
        0x32 );
    ( 2,
      sign_tx
        (Dynamic_fee
           {
             chain_id;
             nonce = nonce2;
             max_priority_fee_per_gas = priority;
             max_fee_per_gas = max_fee;
             gas_limit;
             to_;
             value;
             data;
             access_list;
           })
        0x33 );
    ( 4,
      sign_tx
        (Set_code
           {
             chain_id;
             nonce = nonce4;
             max_priority_fee_per_gas = priority;
             max_fee_per_gas = max_fee;
             gas_limit = uint 100_000;
             to_ = recipient;
             value = Evm_types.Uint256.zero;
             data = "";
             access_list = [];
             authorization_list = [ authorization ];
           })
        0x34 );
  ]

let check_read_methods client =
  let* version =
    rpc client "web3_clientVersion" Evm_rpc.Methods.client_version
  in
  let* network = rpc client "net_version" Evm_rpc.Methods.net_version in
  let* chain_id = rpc client "eth_chainId" Evm_rpc.Methods.chain_id in
  let* height = rpc client "eth_blockNumber" Evm_rpc.Methods.block_number in
  let* _gas_price = rpc client "eth_gasPrice" Evm_rpc.Methods.gas_price in
  let* _priority =
    rpc
      client
      "eth_maxPriorityFeePerGas"
      Evm_rpc.Methods.max_priority_fee_per_gas
  in
  let* balance =
    rpc
      client
      "eth_getBalance"
      (Evm_rpc.Methods.balance sender (Evm_rpc.Types.Tag Latest))
  in
  if Z.sign (Evm_types.Uint256.to_z balance) <= 0 then
    failwith "development sender is not funded";
  let* _nonce =
    rpc
      client
      "eth_getTransactionCount"
      (Evm_rpc.Methods.transaction_count sender (Evm_rpc.Types.Tag Pending))
  in
  let* code =
    rpc
      client
      "eth_getCode"
      (Evm_rpc.Methods.code recipient (Evm_rpc.Types.Tag Latest))
  in
  if code <> "" then failwith "fresh recipient unexpectedly has code";
  let identity = address "0x0000000000000000000000000000000000000004" in
  let call_request =
    Evm_rpc.Types.transaction_request ~to_:identity ~data:"ocaml-evm" ()
  in
  let* call_result =
    rpc client "eth_call" (Evm_rpc.Methods.call call_request)
  in
  if call_result <> "ocaml-evm" then
    failwith "identity precompile result mismatch";
  let estimate_request =
    Evm_rpc.Types.transaction_request ~from:sender ~to_:recipient ()
  in
  let* estimate =
    rpc client "eth_estimateGas" (Evm_rpc.Methods.estimate_gas estimate_request)
  in
  if Z.lt (Evm_types.Uint256.to_z estimate) (Z.of_int 21_000) then
    failwith "transfer gas estimate is below intrinsic gas";
  let history_method =
    result
      "build fee history request"
      (Evm_rpc.Methods.fee_history
         ~block_count:(uint 1)
         ~newest_block:(`Tag Latest)
         ~reward_percentiles:[ 50. ]
         ())
  in
  let* history = rpc client "eth_feeHistory" history_method in
  if List.length history.base_fee_per_gas <> 2 then
    failwith "fee history did not include next-block base fee";
  let filter =
    result
      "build log filter"
      (Evm_rpc.Types.log_filter
         ~from_block:(`Tag Latest)
         ~to_block:(`Tag Latest)
         ~addresses:[ recipient ]
         ())
  in
  let* logs = rpc client "eth_getLogs" (Evm_rpc.Methods.logs filter) in
  if logs <> [] then failwith "fresh recipient unexpectedly emitted logs";
  let* block = wait_for_latest_block client in
  let block_hash = Option.get block.hash in
  let* by_hash =
    rpc client "eth_getBlockByHash" (Evm_rpc.Methods.block_by_hash block_hash)
  in
  (match by_hash with
  | Some { hash = Some returned_hash; _ }
    when Evm_types.Hash.equal block_hash returned_hash -> ()
  | _ -> failwith "block-by-hash did not return the requested block");
  let* _historical_balance =
    rpc
      client
      "EIP-1898 eth_getBalance"
      (Evm_rpc.Methods.balance
         sender
         (Evm_rpc.Types.Hash { hash = block_hash; require_canonical = true }))
  in
  Printf.printf
    "  ok read methods client=%S network=%s chain=%s height=%s\n%!"
    version
    network
    (Evm_types.Chain_id.to_z chain_id |> Z.to_string)
    (Evm_types.Uint256.to_z height |> Z.to_string);
  Lwt.return chain_id

let run ~name ~endpoint =
  Printf.printf "conformance: %s (%s)\n%!" name endpoint;
  let client = Evm_rpc_unix.create (Uri.of_string endpoint) in
  let* chain_id = check_read_methods client in
  let* first_nonce =
    rpc
      client
      "sender pending nonce"
      (Evm_rpc.Methods.transaction_count sender (Evm_rpc.Types.Tag Pending))
  in
  let* authority_nonce =
    rpc
      client
      "authority pending nonce"
      (Evm_rpc.Methods.transaction_count authority (Evm_rpc.Types.Tag Pending))
  in
  let rec submit_all = function
    | [] -> Lwt.return_unit
    | (expected_type, signed) :: rest ->
        let* () = submit client ~expected_type signed in
        submit_all rest
  in
  let* () = submit_all (transaction_set chain_id first_nonce authority_nonce) in
  let* () = malformed_envelope client 3 in
  let* () = malformed_envelope client 4 in
  Printf.printf "conformance: %s passed\n%!" name;
  Lwt.return_unit

let usage () =
  Printf.eprintf "usage: rpc_conformance --name CLIENT --endpoint URL\n%!";
  exit 2

let () =
  let name = ref None and endpoint = ref None in
  let specs =
    [
      ("--name", Arg.String (fun value -> name := Some value), "client name");
      ("--endpoint", Arg.String (fun value -> endpoint := Some value), "RPC URL");
    ]
  in
  Arg.parse specs (fun _ -> usage ()) "ocaml-evm RPC conformance";
  match (!name, !endpoint) with
  | Some name, Some endpoint -> (
      try Lwt_main.run (run ~name ~endpoint)
      with Failure message ->
        Printf.eprintf "conformance: %s failed: %s\n%!" name message;
        exit 1)
  | _ -> usage ()
