(** Ethereum ABI codec and contract-description helpers. *)

(** Ethereum Contract ABI encoding: the head/tail scheme used for function call
    data and event/return values.
    {{:https://docs.soliditylang.org/en/latest/abi-spec.html} spec}

    Encoding rejects values that do not fit their ABI representation rather than
    wrapping them, because a wrapped address is a well-formed transaction to the
    wrong recipient. Decoding bounds every length and offset taken from the
    input against the buffer before allocating, and rejects non-canonical words.
*)

type value =
  | Uint of Z.t
  | Int of Z.t
  | Bool of bool
  | Address of string  (** exactly 20 bytes *)
  | FixedBytes of string  (** bytesN, 1..32 bytes, left-aligned *)
  | Bytes of string  (** dynamic *)
  | String of string
  | Array of value list  (** T[] *)
  | FixedArray of value list  (** T[k] *)
  | Tuple of value list

type ty =
  | TUint of int  (** width in bits: a multiple of 8 in 8..256 *)
  | TInt of int  (** width in bits: a multiple of 8 in 8..256 *)
  | TBool
  | TAddress
  | TFixedBytes of int  (** 1..32 *)
  | TBytes
  | TString
  | TArray of ty
  | TFixedArray of ty * int
  | TTuple of ty list

type limits = {
  max_input_bytes : int;
  max_dynamic_bytes : int;
  max_nesting : int;
  max_elements : int;
  max_contract_items : int;
  max_string_bytes : int;
}

val default_limits : limits
(** Conservative defaults for untrusted ABI bytes, type strings, and JSON
    descriptions. Callers that intentionally handle larger contracts can use the
    [*_with_limits] functions with an explicit policy. *)

val keccak : string -> string
(** keccak256 with Ethereum's pre-NIST padding -- not NIST SHA3-256. *)

val selector : string -> string
(** First 4 bytes of [keccak signature], e.g.
    [selector "transfer(address,uint256)"]. *)

val encode : value list -> (string, string) result
(** [Error] if any value is out of range for its ABI type: a non-negative [Uint]
    below 2^256, an [Int] within a signed 256-bit word, an [Address] of exactly
    20 bytes, a [FixedBytes] of 1..32.

    Note that [value] carries no declared width, so [Uint]/[Int] are checked
    against the 256-bit word rather than against a [uint8] or [int32]; per-width
    checking happens on the decode side, where a {!ty} is available. *)

val encode_call : signature:string -> value list -> (string, string) result
(** [selector signature] followed by the encoded arguments. *)

val encode_exn : value list -> string
(** For call sites with statically known values, such as constants and test
    vectors.
    @raise Invalid_argument where {!encode} would return [Error]. *)

val encode_call_exn : signature:string -> value list -> string
(** @raise Invalid_argument where {!encode_call} would return [Error]. *)

val decode : ty list -> string -> (value list, string) result
(** [Error] on truncated input, an offset or length outside the buffer, an
    element count too large for the bytes remaining, an invalid width in [tys],
    or a non-canonical word (a [bool] other than 0/1, an address with non-zero
    high bytes, a [bytesN] with non-zero padding, or a value outside its
    declared [uintN]/[intN] range). Never raises. *)

val decode_with_limits :
  limits -> ty list -> string -> (value list, string) result

val decode_call : ty list -> string -> (value list, string) result
(** Strip the 4-byte selector, then {!decode} the parameters. *)

val decode_call_with_limits :
  limits -> ty list -> string -> (value list, string) result

val to_z : value -> Z.t option
(** [Some] for [Uint], [Int] and [Bool]; [None] otherwise. *)

val canonical_type : ty -> string
(** Solidity canonical spelling used when constructing selectors. *)

val ty_of_string : string -> (ty, string) result
(** Parse a canonical Solidity ABI type, including nested array suffixes. *)

val ty_of_string_with_limits : limits -> string -> (ty, string) result

type parameter = { name : string; ty : ty; indexed : bool }

type item =
  | Function of {
      name : string;
      inputs : parameter list;
      outputs : parameter list;
      state_mutability : string option;
    }
  | Event of { name : string; inputs : parameter list; anonymous : bool }
  | Error of { name : string; inputs : parameter list }
  | Constructor of { inputs : parameter list; state_mutability : string option }
  | Fallback
  | Receive

val item_of_yojson : Yojson.Safe.t -> (item, string) result
val contract_of_yojson : Yojson.Safe.t -> (item list, string) result

val item_of_yojson_with_limits :
  limits -> Yojson.Safe.t -> (item, string) result

val contract_of_yojson_with_limits :
  limits -> Yojson.Safe.t -> (item list, string) result

val contract_of_json_string : string -> (item list, string) result

val contract_of_json_string_with_limits :
  limits -> string -> (item list, string) result
(** These string entry points check the raw byte length before invoking the JSON
    parser. Prefer them when the ABI description originates outside the trust
    boundary. *)

val function_signature : string -> parameter list -> string
