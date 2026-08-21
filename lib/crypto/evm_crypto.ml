module Hardened = Mirage_crypto_ec.P256k1.Dsa
module Recovery = Mirage_crypto_blockchain.Secp256k1

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

let public_key = Hardened.pub_of_priv

let address key =
  let encoded = public_key_to_bytes ~compress:false key in
  let xy = String.sub encoded 1 64 in
  let hash =
    Digestif.KECCAK_256.digest_string xy |> Digestif.KECCAK_256.to_raw_string
  in
  Result.get_ok (Evm_types.Address.of_bytes (String.sub hash 12 20))

let public_equal a b =
  String.equal (public_key_to_bytes a) (public_key_to_bytes b)

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
          public_key_of_bytes (Recovery.point_to_octets ~compress:false point))

let sign_digest ~nonce key digest =
  if String.length nonce <> 32 then Error `Invalid_nonce
  else
    try
      let r_raw, s_raw =
        Hardened.sign ~key ~k:nonce (Evm_types.Hash.to_bytes digest)
      in
      let r = Evm_types.z_of_be r_raw and s0 = Evm_types.z_of_be s_raw in
      let s =
        if Z.gt s0 Evm_types.Signature.half_curve_order then
          Z.sub Evm_types.Signature.curve_order s0
        else s0
      in
      let expected = public_key key in
      let rec find = function
        | [] -> Error `Recovery_failed
        | parity :: rest -> (
            match Evm_types.Signature.make ~y_parity:parity ~r ~s with
            | Error _ -> Error `Recovery_failed
            | Ok signature -> (
                match recover digest signature with
                | Ok recovered when public_equal recovered expected ->
                    Ok signature
                | _ -> find rest))
      in
      find [ 0; 1 ]
    with Invalid_argument _ -> Error `Invalid_nonce

let verify key digest signature =
  let bytes = Evm_types.Signature.to_bytes signature in
  let r = String.sub bytes 0 32 and s = String.sub bytes 32 32 in
  Hardened.verify ~key (r, s) (Evm_types.Hash.to_bytes digest)
