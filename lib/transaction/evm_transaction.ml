module R = Evm_rlp

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

let ( >>= ) = Result.bind
let u x = R.of_z (Evm_types.Uint256.to_z x)
let chain x = R.of_z (Evm_types.Chain_id.to_z x)
let str x = R.Str x

let destination = function
  | Create -> str ""
  | Call x -> str (Evm_types.Address.to_bytes x)

let access_list xs =
  R.List
    (List.map
       (fun (address, keys) ->
         R.List
           [
             str (Evm_types.Address.to_bytes address);
             R.List
               (List.map
                  (fun key -> str (Evm_types.Storage_key.to_bytes key))
                  keys);
           ])
       xs)

let authorization a =
  R.List
    [
      u a.chain_id;
      str (Evm_types.Address.to_bytes a.address);
      u a.nonce;
      R.of_int (Evm_types.Signature.y_parity a.signature);
      R.of_z (Evm_types.Signature.r a.signature);
      R.of_z (Evm_types.Signature.s a.signature);
    ]

let base_legacy nonce gas_price gas_limit to_ value data =
  [ u nonce; u gas_price; u gas_limit; destination to_; u value; str data ]

let payload = function
  | Legacy x -> (
      let fields =
        base_legacy x.nonce x.gas_price x.gas_limit x.to_ x.value x.data
      in
      ( None,
        fields
        @
        match x.chain_id with
        | None -> []
        | Some id -> [ chain id; R.of_int 0; R.of_int 0 ] ))
  | Access_list x ->
      ( Some '\001',
        [
          chain x.chain_id;
          u x.nonce;
          u x.gas_price;
          u x.gas_limit;
          destination x.to_;
          u x.value;
          str x.data;
          access_list x.access_list;
        ] )
  | Dynamic_fee x ->
      ( Some '\002',
        [
          chain x.chain_id;
          u x.nonce;
          u x.max_priority_fee_per_gas;
          u x.max_fee_per_gas;
          u x.gas_limit;
          destination x.to_;
          u x.value;
          str x.data;
          access_list x.access_list;
        ] )
  | Blob x ->
      ( Some '\003',
        [
          chain x.chain_id;
          u x.nonce;
          u x.max_priority_fee_per_gas;
          u x.max_fee_per_gas;
          u x.gas_limit;
          str (Evm_types.Address.to_bytes x.to_);
          u x.value;
          str x.data;
          access_list x.access_list;
          u x.max_fee_per_blob_gas;
          R.List
            (List.map
               (fun h -> str (Evm_types.Hash.to_bytes h))
               x.blob_versioned_hashes);
        ] )
  | Set_code x ->
      ( Some '\004',
        [
          chain x.chain_id;
          u x.nonce;
          u x.max_priority_fee_per_gas;
          u x.max_fee_per_gas;
          u x.gas_limit;
          str (Evm_types.Address.to_bytes x.to_);
          u x.value;
          str x.data;
          access_list x.access_list;
          R.List (List.map authorization x.authorization_list);
        ] )

let validate = function
  | Blob x when x.blob_versioned_hashes = [] ->
      Error "EIP-4844 transaction requires at least one versioned hash"
  | Blob x
    when List.exists
           (fun h -> (Evm_types.Hash.to_bytes h).[0] <> '\001')
           x.blob_versioned_hashes ->
      Error "EIP-4844 versioned hashes must use version 0x01"
  | Dynamic_fee x
    when Evm_types.Uint256.compare x.max_priority_fee_per_gas x.max_fee_per_gas
         > 0 -> Error "priority fee exceeds max fee"
  | Blob x
    when Evm_types.Uint256.compare x.max_priority_fee_per_gas x.max_fee_per_gas
         > 0 -> Error "priority fee exceeds max fee"
  | Set_code x
    when Evm_types.Uint256.compare x.max_priority_fee_per_gas x.max_fee_per_gas
         > 0 -> Error "priority fee exceeds max fee"
  | Set_code x when x.authorization_list = [] ->
      Error "EIP-7702 authorization list must be non-empty"
  | _ -> Ok ()

let encode_unsigned tx =
  validate tx >>= fun () ->
  let tag, fields = payload tx in
  let encoded = R.encode (R.List fields) in
  Ok
    (match tag with
    | None -> encoded
    | Some tag -> String.make 1 tag ^ encoded)

let digest raw =
  Digestif.KECCAK_256.digest_string raw
  |> Digestif.KECCAK_256.to_raw_string |> Evm_types.Hash.of_bytes
  |> Result.get_ok

let signing_hash tx = encode_unsigned tx |> Result.map digest

let sign ~nonce key transaction =
  signing_hash transaction >>= fun hash ->
  Evm_crypto.sign_digest ~nonce key hash
  |> Result.map_error (Format.asprintf "%a" Evm_crypto.pp_error)
  |> Result.map (fun signature -> { transaction; signature })

let signed_fields tx signature =
  let _, fields = payload tx in
  match tx with
  | Legacy x ->
      let base =
        base_legacy x.nonce x.gas_price x.gas_limit x.to_ x.value x.data
      in
      let parity = Z.of_int (Evm_types.Signature.y_parity signature) in
      let v =
        match x.chain_id with
        | None -> Z.add (Z.of_int 27) parity
        | Some id ->
            Z.add
              (Z.of_int 35)
              (Z.add (Z.mul (Z.of_int 2) (Evm_types.Chain_id.to_z id)) parity)
      in
      base
      @ [
          R.of_z v;
          R.of_z (Evm_types.Signature.r signature);
          R.of_z (Evm_types.Signature.s signature);
        ]
  | _ ->
      fields
      @ [
          R.of_int (Evm_types.Signature.y_parity signature);
          R.of_z (Evm_types.Signature.r signature);
          R.of_z (Evm_types.Signature.s signature);
        ]

let encode_signed signed =
  validate signed.transaction >>= fun () ->
  let tag, _ = payload signed.transaction in
  let raw =
    R.encode (R.List (signed_fields signed.transaction signed.signature))
  in
  Ok
    (match tag with
    | None -> raw
    | Some tag -> String.make 1 tag ^ raw)

let hash signed = encode_signed signed |> Result.map digest

let sender signed =
  signing_hash signed.transaction >>= fun digest ->
  Evm_crypto.recover digest signed.signature
  |> Result.map_error (Format.asprintf "%a" Evm_crypto.pp_error)
  |> Result.map Evm_crypto.address

let authorization_signing_hash ~chain_id ~address ~nonce =
  let encoded =
    R.encode
      (R.List [ u chain_id; str (Evm_types.Address.to_bytes address); u nonce ])
  in
  digest ("\005" ^ encoded)

let as_list = function
  | R.List xs -> Ok xs
  | _ -> Error "expected RLP list"

let as_str = function
  | R.Str s -> Ok s
  | _ -> Error "expected RLP string"

let scalar_z r =
  as_str r >>= fun bytes ->
  if String.length bytes > 0 && bytes.[0] = '\000' then
    Error "transaction scalar has a leading zero byte"
  else Ok (Evm_types.z_of_be bytes)

let scalar r =
  scalar_z r >>= fun z ->
  Evm_types.Uint256.of_z z
  |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)

let chain_id r =
  scalar_z r >>= fun z ->
  Evm_types.Chain_id.of_z z
  |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)

let address r =
  as_str r >>= fun s ->
  Evm_types.Address.of_bytes s
  |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)

let destination_of_rlp r =
  as_str r >>= function
  | "" -> Ok Create
  | bytes ->
      Evm_types.Address.of_bytes bytes
      |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)
      |> Result.map (fun a -> Call a)

let access_list_of_rlp r =
  as_list r >>= fun entries ->
  List.fold_left
    (fun acc entry ->
      acc >>= fun out ->
      as_list entry >>= function
      | [ a; keys ] ->
          address a >>= fun a ->
          as_list keys >>= fun keys ->
          List.fold_left
            (fun acc key ->
              acc >>= fun out ->
              as_str key >>= fun raw ->
              Evm_types.Storage_key.of_bytes raw
              |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)
              |> Result.map (fun key -> key :: out))
            (Ok [])
            keys
          |> Result.map (fun keys -> (a, List.rev keys) :: out)
      | _ -> Error "access-list entry must contain address and storage keys")
    (Ok [])
    entries
  |> Result.map List.rev

let signature parity r s =
  scalar_z parity >>= fun parity_z ->
  if not (Z.fits_int parity_z) then Error "signature parity is out of range"
  else
    scalar_z r >>= fun r ->
    scalar_z s >>= fun s ->
    Evm_types.Signature.make ~y_parity:(Z.to_int parity_z) ~r ~s
    |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)

let authorization_of_rlp r =
  as_list r >>= function
  | [ cid; addr; nonce; parity; r; s ] ->
      scalar cid >>= fun chain_id ->
      address addr >>= fun address ->
      scalar nonce >>= fun nonce ->
      signature parity r s >>= fun signature ->
      Ok { chain_id; address; nonce; signature }
  | _ -> Error "authorization must have six fields"

let authorizations r =
  as_list r >>= fun xs ->
  List.fold_left
    (fun acc x ->
      acc >>= fun out ->
      authorization_of_rlp x |> Result.map (fun x -> x :: out))
    (Ok [])
    xs
  |> Result.map List.rev

let hashes r =
  as_list r >>= fun xs ->
  List.fold_left
    (fun acc x ->
      acc >>= fun out ->
      as_str x >>= fun raw ->
      Evm_types.Hash.of_bytes raw
      |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)
      |> Result.map (fun h -> h :: out))
    (Ok [])
    xs
  |> Result.map List.rev

let legacy fields =
  match fields with
  | [ nonce; gas_price; gas_limit; to_; value; data; v; r; s ] ->
      scalar nonce >>= fun nonce ->
      scalar gas_price >>= fun gas_price ->
      scalar gas_limit >>= fun gas_limit ->
      destination_of_rlp to_ >>= fun to_ ->
      scalar value >>= fun value ->
      as_str data >>= fun data ->
      scalar_z v >>= fun v ->
      let parity_and_chain =
        if Z.equal v (Z.of_int 27) || Z.equal v (Z.of_int 28) then
          Ok (Z.to_int (Z.sub v (Z.of_int 27)), None)
        else if Z.geq v (Z.of_int 35) then
          let parity = Z.to_int (Z.erem (Z.sub v (Z.of_int 35)) (Z.of_int 2)) in
          let cid = Z.div (Z.sub v (Z.of_int (35 + parity))) (Z.of_int 2) in
          Evm_types.Chain_id.of_z cid
          |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)
          |> Result.map (fun c -> (parity, Some c))
        else Error "legacy v is neither pre-EIP-155 nor EIP-155"
      in
      parity_and_chain >>= fun (parity, chain_id) ->
      signature (R.of_int parity) r s >>= fun signature ->
      Ok
        {
          transaction =
            Legacy { nonce; gas_price; gas_limit; to_; value; data; chain_id };
          signature;
        }
  | _ -> Error "legacy signed transaction must have nine fields"

let typed tag fields =
  let finish transaction parity r s =
    signature parity r s >>= fun signature ->
    validate transaction >>= fun () -> Ok { transaction; signature }
  in
  match (tag, fields) with
  | ( 1,
      [
        cid; nonce; gas_price; gas_limit; to_; value; data; access; parity; r; s;
      ] ) ->
      chain_id cid >>= fun chain_id ->
      scalar nonce >>= fun nonce ->
      scalar gas_price >>= fun gas_price ->
      scalar gas_limit >>= fun gas_limit ->
      destination_of_rlp to_ >>= fun to_ ->
      scalar value >>= fun value ->
      as_str data >>= fun data ->
      access_list_of_rlp access >>= fun access_list ->
      finish
        (Access_list
           {
             chain_id;
             nonce;
             gas_price;
             gas_limit;
             to_;
             value;
             data;
             access_list;
           })
        parity
        r
        s
  | ( 2,
      [
        cid;
        nonce;
        priority;
        fee;
        gas_limit;
        to_;
        value;
        data;
        access;
        parity;
        r;
        s;
      ] ) ->
      chain_id cid >>= fun chain_id ->
      scalar nonce >>= fun nonce ->
      scalar priority >>= fun max_priority_fee_per_gas ->
      scalar fee >>= fun max_fee_per_gas ->
      scalar gas_limit >>= fun gas_limit ->
      destination_of_rlp to_ >>= fun to_ ->
      scalar value >>= fun value ->
      as_str data >>= fun data ->
      access_list_of_rlp access >>= fun access_list ->
      finish
        (Dynamic_fee
           {
             chain_id;
             nonce;
             max_priority_fee_per_gas;
             max_fee_per_gas;
             gas_limit;
             to_;
             value;
             data;
             access_list;
           })
        parity
        r
        s
  | ( 3,
      [
        cid;
        nonce;
        priority;
        fee;
        gas_limit;
        to_;
        value;
        data;
        access;
        blob_fee;
        versioned;
        parity;
        r;
        s;
      ] ) ->
      chain_id cid >>= fun chain_id ->
      scalar nonce >>= fun nonce ->
      scalar priority >>= fun max_priority_fee_per_gas ->
      scalar fee >>= fun max_fee_per_gas ->
      scalar gas_limit >>= fun gas_limit ->
      address to_ >>= fun to_ ->
      scalar value >>= fun value ->
      as_str data >>= fun data ->
      access_list_of_rlp access >>= fun access_list ->
      scalar blob_fee >>= fun max_fee_per_blob_gas ->
      hashes versioned >>= fun blob_versioned_hashes ->
      finish
        (Blob
           {
             chain_id;
             nonce;
             max_priority_fee_per_gas;
             max_fee_per_gas;
             gas_limit;
             to_;
             value;
             data;
             access_list;
             max_fee_per_blob_gas;
             blob_versioned_hashes;
           })
        parity
        r
        s
  | ( 4,
      [
        cid;
        nonce;
        priority;
        fee;
        gas_limit;
        to_;
        value;
        data;
        access;
        auths;
        parity;
        r;
        s;
      ] ) ->
      chain_id cid >>= fun chain_id ->
      scalar nonce >>= fun nonce ->
      scalar priority >>= fun max_priority_fee_per_gas ->
      scalar fee >>= fun max_fee_per_gas ->
      scalar gas_limit >>= fun gas_limit ->
      address to_ >>= fun to_ ->
      scalar value >>= fun value ->
      as_str data >>= fun data ->
      access_list_of_rlp access >>= fun access_list ->
      authorizations auths >>= fun authorization_list ->
      finish
        (Set_code
           {
             chain_id;
             nonce;
             max_priority_fee_per_gas;
             max_fee_per_gas;
             gas_limit;
             to_;
             value;
             data;
             access_list;
             authorization_list;
           })
        parity
        r
        s
  | 1, _ -> Error "EIP-2930 signed transaction must have eleven fields"
  | 2, _ -> Error "EIP-1559 signed transaction must have twelve fields"
  | 3, _ -> Error "EIP-4844 signed transaction must have fourteen fields"
  | 4, _ -> Error "EIP-7702 signed transaction must have thirteen fields"
  | _ -> Error "unsupported typed transaction"

let decode_signed raw =
  if raw = "" then Error "empty transaction"
  else
    let first = Char.code raw.[0] in
    if first >= 1 && first <= 4 then
      R.decode (String.sub raw 1 (String.length raw - 1))
      >>= as_list >>= typed first
    else if first < 0x80 then
      Error (Printf.sprintf "unsupported transaction type 0x%02x" first)
    else R.decode raw >>= as_list >>= legacy
