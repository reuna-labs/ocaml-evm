module Hardened = Mirage_crypto_secp256k1
module Recovery = Mirage_crypto_secp256k1

type private_key = Hardened.priv
type public_key = Hardened.pub

type error =
  [ `Invalid_key of string
  | `Invalid_digest
  | `Invalid_nonce
  | `Recovery_failed ]

let pp_error ppf = function
  | `Invalid_key s -> Format.fprintf ppf "invalid secp256k1 key: %s" s
  | `Invalid_digest -> Format.pp_print_string ppf "digest must be 32 bytes"
  | `Invalid_nonce ->
      Format.pp_print_string ppf "nonce must be a valid secp256k1 scalar"
  | `Recovery_failed -> Format.pp_print_string ppf "public-key recovery failed"

let private_key_of_bytes b =
  match Hardened.priv_of_octets b with
  | Ok k -> Ok k
  | Error _ -> Error (`Invalid_key "private key")

let public_key_of_bytes b =
  match Hardened.pub_of_octets b with
  | Ok k -> Ok k
  | Error _ -> Error (`Invalid_key "public key")

let public_key_to_bytes ?(compress = false) k =
  Hardened.pub_to_octets ~compress k

let public_key key = Hardened.pub_of_priv key

let address key =
  let encoded = public_key_to_bytes ~compress:false key in
  let xy = String.sub encoded 1 64 in
  let hash =
    Digestif.KECCAK_256.digest_string xy |> Digestif.KECCAK_256.to_raw_string
  in
  Result.get_ok (Evm_types.Address.of_bytes (String.sub hash 12 20))

let recovery_signature sig_ =
  Recovery.signature_of_octets (Evm_types.Signature.to_bytes sig_)

let recover digest sig_ =
  match recovery_signature sig_ with
  | Error _ -> Error `Recovery_failed
  | Ok signature -> (
      let recid = Evm_types.Signature.y_parity sig_ in
      match
        Recovery.recover ~msg:(Evm_types.Hash.to_bytes digest) signature ~recid
      with
      | Error _ -> Error `Recovery_failed
      | Ok point ->
          Ok point)

let sign_digest ~nonce key digest =
  try
    let signature, recid = Hardened.sign_recoverable ~nonce ~key (Evm_types.Hash.to_bytes digest) in
    if recid > 1 then Error `Recovery_failed
    else
      let bytes = Hardened.signature_to_octets signature in
      let r = Evm_types.z_of_be (String.sub bytes 0 32)
      and s = Evm_types.z_of_be (String.sub bytes 32 32) in
      match Evm_types.Signature.make ~y_parity:recid ~r ~s with
      | Ok signature -> Ok signature
      | Error _ -> Error `Recovery_failed
  with Invalid_argument _ -> Error `Invalid_nonce

let verify key digest signature =
  match Hardened.signature_of_octets (Evm_types.Signature.to_bytes signature) with
  | Error _ -> false
  | Ok signature -> Hardened.verify ~key signature (Evm_types.Hash.to_bytes digest)
