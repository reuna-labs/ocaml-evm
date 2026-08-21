val client_version : string Method.t
val net_version : string Method.t
val chain_id : Evm_types.Chain_id.t Method.t
val block_number : Evm_types.Uint256.t Method.t
val gas_price : Evm_types.Uint256.t Method.t
val max_priority_fee_per_gas : Evm_types.Uint256.t Method.t

val balance :
  Evm_types.Address.t -> Types.block_ref -> Evm_types.Uint256.t Method.t

val transaction_count :
  Evm_types.Address.t -> Types.block_ref -> Evm_types.Uint256.t Method.t

val code : Evm_types.Address.t -> Types.block_ref -> string Method.t

val call :
  ?block:Types.block_ref -> Types.transaction_request -> string Method.t

val estimate_gas :
  ?block:Types.block_ref ->
  Types.transaction_request ->
  Evm_types.Uint256.t Method.t

val fee_history :
  block_count:Evm_types.Uint256.t ->
  newest_block:Types.block_number ->
  ?reward_percentiles:float list ->
  unit ->
  (Types.fee_history Method.t, string) result

val send_raw_transaction :
  Evm_transaction.signed -> (Evm_types.Hash.t Method.t, string) result

val transaction_receipt : Evm_types.Hash.t -> Types.receipt option Method.t
val logs : Types.log_filter -> Types.log list Method.t
val block_by_number : Types.block_number -> Types.block option Method.t
val block_by_hash : Evm_types.Hash.t -> Types.block option Method.t
