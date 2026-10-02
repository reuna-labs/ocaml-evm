(** Native libsecp256k1 signing and recovery. Public derivation and signing
    require an initialized Mirage RNG for independent context blinding.
    Applications supply entropy; this library performs no OS I/O. *)

type private_key
type public_key

type error =
  [ `Invalid_key of string
  | `Invalid_digest
  | `Invalid_nonce
  | `Recovery_failed ]

val pp_error : Format.formatter -> error -> unit
val private_key_of_bytes : string -> (private_key, error) result
val public_key_of_bytes : string -> (public_key, error) result
val public_key_to_bytes : ?compress:bool -> public_key -> string
val public_key : private_key -> public_key
val address : public_key -> Evm_types.Address.t

val sign_digest :
  nonce:string ->
  private_key ->
  Evm_types.Hash.t ->
  (Evm_types.Signature.t, error) result
(** [nonce] is exactly 32 bytes of independent secret entropy in the scalar
    range. It must never be reused across messages. Context blinding also
    requires an initialized Mirage RNG; it does not change the signature. *)

val recover :
  Evm_types.Hash.t -> Evm_types.Signature.t -> (public_key, error) result

val verify : public_key -> Evm_types.Hash.t -> Evm_types.Signature.t -> bool
