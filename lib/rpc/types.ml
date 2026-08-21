type block_tag = Latest | Safe | Finalized | Earliest | Pending
type block_number = [ `Tag of block_tag | `Number of Evm_types.Uint256.t ]

type block_ref =
  | Tag of block_tag
  | Number of Evm_types.Uint256.t
  | Hash of { hash : Evm_types.Hash.t; require_canonical : bool }

type transaction_request = {
  from : Evm_types.Address.t option;
  to_ : Evm_types.Address.t option;
  gas : Evm_types.Uint256.t option;
  gas_price : Evm_types.Uint256.t option;
  max_fee_per_gas : Evm_types.Uint256.t option;
  max_priority_fee_per_gas : Evm_types.Uint256.t option;
  value : Evm_types.Uint256.t option;
  data : string option;
}

let transaction_request ?from ?to_ ?gas ?gas_price ?max_fee_per_gas
    ?max_priority_fee_per_gas ?value ?data () =
  {
    from;
    to_;
    gas;
    gas_price;
    max_fee_per_gas;
    max_priority_fee_per_gas;
    value;
    data;
  }

type topic = Any | One of Evm_types.Hash.t | Or of Evm_types.Hash.t list

type log_filter = {
  from_block : block_number option;
  to_block : block_number option;
  block_hash : Evm_types.Hash.t option;
  addresses : Evm_types.Address.t list;
  topics : topic list;
}

let log_filter ?from_block ?to_block ?block_hash ?(addresses = [])
    ?(topics = []) () =
  if
    Option.is_some block_hash
    && (Option.is_some from_block || Option.is_some to_block)
  then Error "blockHash cannot be combined with fromBlock or toBlock"
  else if
    List.exists
      (function
        | Or [] -> true
        | _ -> false)
      topics
  then Error "a topic OR-list cannot be empty"
  else if List.length topics > 4 then
    Error "Ethereum log filters support at most four topic positions"
  else Ok { from_block; to_block; block_hash; addresses; topics }

type log = {
  removed : bool;
  log_index : Evm_types.Uint256.t option;
  transaction_index : Evm_types.Uint256.t option;
  transaction_hash : Evm_types.Hash.t option;
  block_hash : Evm_types.Hash.t option;
  block_number : Evm_types.Uint256.t option;
  address : Evm_types.Address.t;
  data : string;
  topics : Evm_types.Hash.t list;
}

type receipt = {
  transaction_hash : Evm_types.Hash.t;
  transaction_index : Evm_types.Uint256.t;
  block_hash : Evm_types.Hash.t option;
  block_number : Evm_types.Uint256.t option;
  from : Evm_types.Address.t;
  to_ : Evm_types.Address.t option;
  contract_address : Evm_types.Address.t option;
  cumulative_gas_used : Evm_types.Uint256.t;
  gas_used : Evm_types.Uint256.t;
  effective_gas_price : Evm_types.Uint256.t option;
  status : bool option;
  type_ : Evm_types.Uint256.t option;
  logs : log list;
}

type block = {
  number : Evm_types.Uint256.t option;
  hash : Evm_types.Hash.t option;
  parent_hash : Evm_types.Hash.t;
  timestamp : Evm_types.Uint256.t;
  gas_limit : Evm_types.Uint256.t;
  gas_used : Evm_types.Uint256.t;
  base_fee_per_gas : Evm_types.Uint256.t option;
  blob_gas_used : Evm_types.Uint256.t option;
  excess_blob_gas : Evm_types.Uint256.t option;
  transactions : Evm_types.Hash.t list;
}

type fee_history = {
  oldest_block : Evm_types.Uint256.t;
  base_fee_per_gas : Evm_types.Uint256.t list;
  gas_used_ratio : float list;
  reward : Evm_types.Uint256.t list list option;
  base_fee_per_blob_gas : Evm_types.Uint256.t list option;
  blob_gas_used_ratio : float list option;
}

let ( >>= ) = Result.bind
let quantity x = `String (Evm_types.Uint256.to_quantity x)
let address x = `String (Evm_types.Address.to_hex x)
let hash x = `String (Evm_types.Hash.to_hex x)
let data x = `String (Evm_types.Hex.encode x)

let block_ref_to_yojson = function
  | Tag Latest -> `String "latest"
  | Tag Safe -> `String "safe"
  | Tag Finalized -> `String "finalized"
  | Tag Earliest -> `String "earliest"
  | Tag Pending -> `String "pending"
  | Number n -> quantity n
  | Hash { hash = value; require_canonical } ->
      `Assoc
        [
          ("blockHash", hash value);
          ("requireCanonical", `Bool require_canonical);
        ]

let block_number_to_yojson = function
  | `Tag tag -> block_ref_to_yojson (Tag tag)
  | `Number number -> block_ref_to_yojson (Number number)

let add_opt name encode value fields =
  match value with
  | None -> fields
  | Some value -> (name, encode value) :: fields

let transaction_request_to_yojson (t : transaction_request) =
  []
  |> add_opt "from" address t.from
  |> add_opt "to" address t.to_
  |> add_opt "gas" quantity t.gas
  |> add_opt "gasPrice" quantity t.gas_price
  |> add_opt "maxFeePerGas" quantity t.max_fee_per_gas
  |> add_opt "maxPriorityFeePerGas" quantity t.max_priority_fee_per_gas
  |> add_opt "value" quantity t.value
  |> add_opt "data" data t.data |> List.rev
  |> fun fields -> `Assoc fields

let topic_to_yojson = function
  | Any -> `Null
  | One topic -> hash topic
  | Or topics -> `List (List.map hash topics)

let log_filter_to_yojson (f : log_filter) =
  let fields =
    []
    |> add_opt "fromBlock" block_number_to_yojson f.from_block
    |> add_opt "toBlock" block_number_to_yojson f.to_block
    |> add_opt "blockHash" hash f.block_hash
  in
  let fields =
    match f.addresses with
    | [] -> fields
    | [ one ] -> ("address", address one) :: fields
    | many -> ("address", `List (List.map address many)) :: fields
  in
  let fields =
    match f.topics with
    | [] -> fields
    | topics -> ("topics", `List (List.map topic_to_yojson topics)) :: fields
  in
  `Assoc (List.rev fields)

let field name fields =
  match List.assoc_opt name fields with
  | Some value -> Ok value
  | None -> Error ("missing field " ^ name)

let string = function
  | `String value -> Ok value
  | _ -> Error "expected a string"

let bool = function
  | `Bool value -> Ok value
  | _ -> Error "expected a boolean"

let decode_quantity json =
  string json >>= fun value ->
  Evm_types.Uint256.of_quantity value
  |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)

let decode_hash json =
  string json >>= fun value ->
  Evm_types.Hash.of_hex value
  |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)

let decode_address json =
  string json >>= fun value ->
  Evm_types.Address.of_hex value
  |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)

let decode_data json =
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

let optional_field name decode fields =
  match List.assoc_opt name fields with
  | None | Some `Null -> Ok None
  | Some x -> Result.map Option.some (decode x)

let log_of_yojson = function
  | `Assoc fields ->
      (match List.assoc_opt "removed" fields with
      | None -> Ok false
      | Some x -> bool x)
      >>= fun removed ->
      optional_field "logIndex" decode_quantity fields >>= fun log_index ->
      optional_field "transactionIndex" decode_quantity fields
      >>= fun transaction_index ->
      optional_field "transactionHash" decode_hash fields
      >>= fun transaction_hash ->
      optional_field "blockHash" decode_hash fields >>= fun block_hash ->
      optional_field "blockNumber" decode_quantity fields
      >>= fun block_number ->
      field "address" fields >>= decode_address >>= fun address ->
      field "data" fields >>= decode_data >>= fun data ->
      field "topics" fields >>= list decode_hash >>= fun topics ->
      Ok
        {
          removed;
          log_index;
          transaction_index;
          transaction_hash;
          block_hash;
          block_number;
          address;
          data;
          topics;
        }
  | _ -> Error "log must be an object"

let receipt_of_yojson = function
  | `Assoc fields ->
      field "transactionHash" fields >>= decode_hash >>= fun transaction_hash ->
      field "transactionIndex" fields >>= decode_quantity
      >>= fun transaction_index ->
      optional_field "blockHash" decode_hash fields >>= fun block_hash ->
      optional_field "blockNumber" decode_quantity fields
      >>= fun block_number ->
      field "from" fields >>= decode_address >>= fun from ->
      optional_field "to" decode_address fields >>= fun to_ ->
      optional_field "contractAddress" decode_address fields
      >>= fun contract_address ->
      field "cumulativeGasUsed" fields >>= decode_quantity
      >>= fun cumulative_gas_used ->
      field "gasUsed" fields >>= decode_quantity >>= fun gas_used ->
      optional_field "effectiveGasPrice" decode_quantity fields
      >>= fun effective_gas_price ->
      optional_field "status" decode_quantity fields >>= fun status_quantity ->
      (match status_quantity with
      | None -> Ok None
      | Some value when Evm_types.Uint256.equal value Evm_types.Uint256.zero ->
          Ok (Some false)
      | Some value when Evm_types.Uint256.equal value Evm_types.Uint256.one ->
          Ok (Some true)
      | Some _ -> Error "receipt status must be 0x0 or 0x1")
      >>= fun status ->
      optional_field "type" decode_quantity fields >>= fun type_ ->
      field "logs" fields >>= list log_of_yojson >>= fun logs ->
      Ok
        {
          transaction_hash;
          transaction_index;
          block_hash;
          block_number;
          from;
          to_;
          contract_address;
          cumulative_gas_used;
          gas_used;
          effective_gas_price;
          status;
          type_;
          logs;
        }
  | _ -> Error "receipt must be an object"

let block_of_yojson = function
  | `Assoc fields ->
      optional_field "number" decode_quantity fields >>= fun number ->
      optional_field "hash" decode_hash fields >>= fun hash ->
      field "parentHash" fields >>= decode_hash >>= fun parent_hash ->
      field "timestamp" fields >>= decode_quantity >>= fun timestamp ->
      field "gasLimit" fields >>= decode_quantity >>= fun gas_limit ->
      field "gasUsed" fields >>= decode_quantity >>= fun gas_used ->
      optional_field "baseFeePerGas" decode_quantity fields
      >>= fun base_fee_per_gas ->
      optional_field "blobGasUsed" decode_quantity fields
      >>= fun blob_gas_used ->
      optional_field "excessBlobGas" decode_quantity fields
      >>= fun excess_blob_gas ->
      field "transactions" fields >>= list decode_hash >>= fun transactions ->
      Ok
        {
          number;
          hash;
          parent_hash;
          timestamp;
          gas_limit;
          gas_used;
          base_fee_per_gas;
          blob_gas_used;
          excess_blob_gas;
          transactions;
        }
  | _ -> Error "block must be an object"

let float = function
  | `Float value -> Ok value
  | `Int value -> Ok (float_of_int value)
  | `Intlit value -> (
      try Ok (float_of_string value) with Failure _ -> Error "invalid number")
  | _ -> Error "expected a number"

let fee_history_of_yojson = function
  | `Assoc fields ->
      field "oldestBlock" fields >>= decode_quantity >>= fun oldest_block ->
      field "baseFeePerGas" fields >>= list decode_quantity
      >>= fun base_fee_per_gas ->
      field "gasUsedRatio" fields >>= list float >>= fun gas_used_ratio ->
      optional_field "reward" (list (list decode_quantity)) fields
      >>= fun reward ->
      optional_field "baseFeePerBlobGas" (list decode_quantity) fields
      >>= fun base_fee_per_blob_gas ->
      optional_field "blobGasUsedRatio" (list float) fields
      >>= fun blob_gas_used_ratio ->
      Ok
        {
          oldest_block;
          base_fee_per_gas;
          gas_used_ratio;
          reward;
          base_fee_per_blob_gas;
          blob_gas_used_ratio;
        }
  | _ -> Error "fee history must be an object"
