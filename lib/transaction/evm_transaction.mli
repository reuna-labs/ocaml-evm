(** Ethereum transaction envelopes through EIP-7702. *)

type destination = Create | Call of Evm_types.Address.t
type access_list = (Evm_types.Address.t * Evm_types.Storage_key.t list) list

type authorization = {
  chain_id : Evm_types.Uint256.t;
  address : Evm_types.Address.t;
  nonce : Evm_types.Uint256.t;
  signature : Evm_types.Signature.t;
}

type t =
  | Legacy of {
      nonce : Evm_types.Uint256.t;
      gas_price : Evm_types.Uint256.t;
      gas_limit : Evm_types.Uint256.t;
      to_ : destination;
      value : Evm_types.Uint256.t;
      data : string;
      chain_id : Evm_types.Chain_id.t option;
    }
  | Access_list of {
      chain_id : Evm_types.Chain_id.t;
      nonce : Evm_types.Uint256.t;
      gas_price : Evm_types.Uint256.t;
      gas_limit : Evm_types.Uint256.t;
      to_ : destination;
      value : Evm_types.Uint256.t;
      data : string;
      access_list : access_list;
    }
  | Dynamic_fee of {
      chain_id : Evm_types.Chain_id.t;
      nonce : Evm_types.Uint256.t;
      max_priority_fee_per_gas : Evm_types.Uint256.t;
      max_fee_per_gas : Evm_types.Uint256.t;
      gas_limit : Evm_types.Uint256.t;
      to_ : destination;
      value : Evm_types.Uint256.t;
      data : string;
      access_list : access_list;
    }
  | Blob of {
      chain_id : Evm_types.Chain_id.t;
      nonce : Evm_types.Uint256.t;
      max_priority_fee_per_gas : Evm_types.Uint256.t;
      max_fee_per_gas : Evm_types.Uint256.t;
      gas_limit : Evm_types.Uint256.t;
      to_ : Evm_types.Address.t;
      value : Evm_types.Uint256.t;
      data : string;
      access_list : access_list;
      max_fee_per_blob_gas : Evm_types.Uint256.t;
      blob_versioned_hashes : Evm_types.Hash.t list;
    }
  | Set_code of {
      chain_id : Evm_types.Chain_id.t;
      nonce : Evm_types.Uint256.t;
      max_priority_fee_per_gas : Evm_types.Uint256.t;
      max_fee_per_gas : Evm_types.Uint256.t;
      gas_limit : Evm_types.Uint256.t;
      to_ : Evm_types.Address.t;
      value : Evm_types.Uint256.t;
      data : string;
      access_list : access_list;
      authorization_list : authorization list;
    }

type signed = { transaction : t; signature : Evm_types.Signature.t }

val validate : t -> (unit, string) result
val encode_unsigned : t -> (string, string) result
val signing_hash : t -> (Evm_types.Hash.t, string) result

val sign :
  nonce:string -> Evm_crypto.private_key -> t -> (signed, string) result

val encode_signed : signed -> (string, string) result
val decode_signed : string -> (signed, string) result
val sender : signed -> (Evm_types.Address.t, string) result
val hash : signed -> (Evm_types.Hash.t, string) result

val authorization_signing_hash :
  chain_id:Evm_types.Uint256.t ->
  address:Evm_types.Address.t ->
  nonce:Evm_types.Uint256.t ->
  Evm_types.Hash.t
