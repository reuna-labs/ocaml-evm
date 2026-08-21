(** EIP-712 typed structured data hashing. *)

type member = { name : string; typ : string }
type schema = (string * member list) list

type t = {
  types : schema;
  primary_type : string;
  domain : Yojson.Safe.t;
  message : Yojson.Safe.t;
}

type limits = {
  max_input_bytes : int;
  max_json_depth : int;
  max_json_nodes : int;
  max_array_length : int;
  max_object_fields : int;
  max_string_bytes : int;
  max_types : int;
  max_members_per_type : int;
  max_identifier_bytes : int;
}

val default_limits : limits
val of_yojson : Yojson.Safe.t -> (t, string) result
val of_yojson_with_limits : limits -> Yojson.Safe.t -> (t, string) result
val of_json_string : string -> (t, string) result
val of_json_string_with_limits : limits -> string -> (t, string) result
val encode_type : schema -> string -> (string, string) result

val encode_type_with_limits :
  limits -> schema -> string -> (string, string) result

val type_hash : schema -> string -> (Evm_types.Hash.t, string) result

val type_hash_with_limits :
  limits -> schema -> string -> (Evm_types.Hash.t, string) result

val hash_struct :
  schema -> string -> Yojson.Safe.t -> (Evm_types.Hash.t, string) result

val hash_struct_with_limits :
  limits ->
  schema ->
  string ->
  Yojson.Safe.t ->
  (Evm_types.Hash.t, string) result

val domain_separator : t -> (Evm_types.Hash.t, string) result

val domain_separator_with_limits :
  limits -> t -> (Evm_types.Hash.t, string) result

val digest : t -> (Evm_types.Hash.t, string) result
(** [keccak256(0x1901 || domainSeparator || hashStruct(message))]. *)

val digest_with_limits : limits -> t -> (Evm_types.Hash.t, string) result
