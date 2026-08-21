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

val transaction_request :
  ?from:Evm_types.Address.t ->
  ?to_:Evm_types.Address.t ->
  ?gas:Evm_types.Uint256.t ->
  ?gas_price:Evm_types.Uint256.t ->
  ?max_fee_per_gas:Evm_types.Uint256.t ->
  ?max_priority_fee_per_gas:Evm_types.Uint256.t ->
  ?value:Evm_types.Uint256.t ->
  ?data:string ->
  unit ->
  transaction_request

type topic = Any | One of Evm_types.Hash.t | Or of Evm_types.Hash.t list

type log_filter = {
  from_block : block_number option;
  to_block : block_number option;
  block_hash : Evm_types.Hash.t option;
  addresses : Evm_types.Address.t list;
  topics : topic list;
}

val log_filter :
  ?from_block:block_number ->
  ?to_block:block_number ->
  ?block_hash:Evm_types.Hash.t ->
  ?addresses:Evm_types.Address.t list ->
  ?topics:topic list ->
  unit ->
  (log_filter, string) result

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

val block_ref_to_yojson : block_ref -> Yojson.Safe.t
val block_number_to_yojson : block_number -> Yojson.Safe.t
val transaction_request_to_yojson : transaction_request -> Yojson.Safe.t
val log_filter_to_yojson : log_filter -> Yojson.Safe.t
val log_of_yojson : Yojson.Safe.t -> (log, string) result
val receipt_of_yojson : Yojson.Safe.t -> (receipt, string) result
val block_of_yojson : Yojson.Safe.t -> (block, string) result
val fee_history_of_yojson : Yojson.Safe.t -> (fee_history, string) result
