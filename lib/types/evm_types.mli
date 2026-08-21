(** Validated primitive types shared by EVM protocols. Raw byte strings are used
    internally; hexadecimal is confined to {!Hex}. *)

type error =
  [ `Invalid_hex of string
  | `Invalid_length of int * int
  | `Invalid_range of string
  | `Non_canonical of string
  | `Checksum_mismatch ]

val pp_error : Format.formatter -> error -> unit

module Hex : sig
  val encode_raw : string -> string

  val encode : string -> string
  (** Lowercase, [0x]-prefixed data encoding. *)

  val decode : string -> (string, error) result
  (** Decode [0x]-prefixed, even-length data. *)

  val encode_quantity : Z.t -> (string, error) result

  val decode_quantity : string -> (Z.t, error) result
  (** Canonical Ethereum quantities: zero is [0x0], and other values have no
      leading zero nibble. *)
end

module Uint256 : sig
  type t

  val zero : t
  val one : t
  val of_z : Z.t -> (t, error) result
  val of_int : int -> (t, error) result
  val to_z : t -> Z.t
  val of_quantity : string -> (t, error) result
  val to_quantity : t -> string
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
end

module Chain_id : sig
  type t

  val of_z : Z.t -> (t, error) result
  val of_int : int -> (t, error) result
  val to_z : t -> Z.t
  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
end

module Address : sig
  type t

  val length : int
  val zero : t
  val of_bytes : string -> (t, error) result
  val to_bytes : t -> string

  val of_hex : string -> (t, error) result
  (** Accept all-lowercase and all-uppercase addresses. Mixed-case input must
      carry a valid EIP-55 checksum. *)

  val to_hex : t -> string
  val to_checksum : t -> string
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val pp : Format.formatter -> t -> unit
end

module Hash : sig
  type t

  val length : int
  val of_bytes : string -> (t, error) result
  val to_bytes : t -> string
  val of_hex : string -> (t, error) result
  val to_hex : t -> string
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val pp : Format.formatter -> t -> unit
end

module Storage_key : sig
  type t

  val of_bytes : string -> (t, error) result
  val to_bytes : t -> string
  val of_hex : string -> (t, error) result
  val to_hex : t -> string
  val equal : t -> t -> bool
end

module Signature : sig
  type t

  val curve_order : Z.t
  val half_curve_order : Z.t
  val make : y_parity:int -> r:Z.t -> s:Z.t -> (t, error) result

  val of_bytes : y_parity:int -> string -> (t, error) result
  (** The byte string is exactly [r || s], two 32-byte big-endian scalars. *)

  val y_parity : t -> int
  val r : t -> Z.t
  val s : t -> Z.t
  val to_bytes : t -> string
  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
end

val z_of_be : string -> Z.t
val be_of_z : len:int -> Z.t -> (string, error) result
