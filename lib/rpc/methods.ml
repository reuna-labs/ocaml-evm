let ( >>= ) = Result.bind

let string = function
  | `String value -> Ok value
  | _ -> Error "expected a string"

let quantity json =
  string json >>= fun value ->
  Evm_types.Uint256.of_quantity value
  |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)

let chain json =
  quantity json >>= fun value ->
  Evm_types.Chain_id.of_z (Evm_types.Uint256.to_z value)
  |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)

let hash json =
  string json >>= fun value ->
  Evm_types.Hash.of_hex value
  |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)

let data json =
  string json >>= fun value ->
  Evm_types.Hex.decode value
  |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)

let list decode = function
  | `List values ->
      List.fold_left
        (fun acc value ->
          acc >>= fun out ->
          decode value |> Result.map (fun value -> value :: out))
        (Ok [])
        values
      |> Result.map List.rev
  | _ -> Error "expected an array"

let nullable decode = function
  | `Null -> Ok None
  | value -> Result.map Option.some (decode value)

let client_version = Method.make ~name:"web3_clientVersion" string
let net_version = Method.make ~name:"net_version" string
let chain_id = Method.make ~name:"eth_chainId" chain
let block_number = Method.make ~name:"eth_blockNumber" quantity
let gas_price = Method.make ~name:"eth_gasPrice" quantity

let max_priority_fee_per_gas =
  Method.make ~name:"eth_maxPriorityFeePerGas" quantity

let balance address block =
  Method.make
    ~name:"eth_getBalance"
    ~params:
      [
        `String (Evm_types.Address.to_hex address);
        Types.block_ref_to_yojson block;
      ]
    quantity

let transaction_count address block =
  Method.make
    ~name:"eth_getTransactionCount"
    ~params:
      [
        `String (Evm_types.Address.to_hex address);
        Types.block_ref_to_yojson block;
      ]
    quantity

let code address block =
  Method.make
    ~name:"eth_getCode"
    ~params:
      [
        `String (Evm_types.Address.to_hex address);
        Types.block_ref_to_yojson block;
      ]
    data

let call ?(block = Types.Tag Latest) request =
  Method.make
    ~name:"eth_call"
    ~params:
      [
        Types.transaction_request_to_yojson request;
        Types.block_ref_to_yojson block;
      ]
    data

let estimate_gas ?block request =
  let params =
    Types.transaction_request_to_yojson request
    ::
    (match block with
    | None -> []
    | Some block -> [ Types.block_ref_to_yojson block ])
  in
  Method.make ~name:"eth_estimateGas" ~params quantity

let fee_history ~block_count ~newest_block ?(reward_percentiles = []) () =
  let rec valid previous = function
    | [] -> true
    | x :: xs ->
        Float.is_finite x && x >= 0. && x <= 100. && x > previous && valid x xs
  in
  let count = Evm_types.Uint256.to_z block_count in
  if Z.sign count <= 0 || Z.gt count (Z.of_int 1024) then
    Error "fee-history block count must be in 1..1024"
  else if not (valid (-1.) reward_percentiles) then
    Error
      "reward percentiles must be finite, strictly increasing values in 0..100"
  else
    Ok
      (Method.make
         ~name:"eth_feeHistory"
         ~params:
           [
             `String (Evm_types.Uint256.to_quantity block_count);
             Types.block_number_to_yojson newest_block;
             `List (List.map (fun value -> `Float value) reward_percentiles);
           ]
         Types.fee_history_of_yojson)

let send_raw_transaction signed =
  Evm_transaction.encode_signed signed
  |> Result.map (fun raw ->
         Method.make
           ~name:"eth_sendRawTransaction"
           ~params:[ `String (Evm_types.Hex.encode raw) ]
           hash)

let transaction_receipt hash_value =
  Method.make
    ~name:"eth_getTransactionReceipt"
    ~params:[ `String (Evm_types.Hash.to_hex hash_value) ]
    (nullable Types.receipt_of_yojson)

let logs filter =
  Method.make
    ~name:"eth_getLogs"
    ~params:[ Types.log_filter_to_yojson filter ]
    (list Types.log_of_yojson)

let block_by_number block =
  Method.make
    ~name:"eth_getBlockByNumber"
    ~params:[ Types.block_number_to_yojson block; `Bool false ]
    (nullable Types.block_of_yojson)

let block_by_hash hash_value =
  Method.make
    ~name:"eth_getBlockByHash"
    ~params:[ `String (Evm_types.Hash.to_hex hash_value); `Bool false ]
    (nullable Types.block_of_yojson)
