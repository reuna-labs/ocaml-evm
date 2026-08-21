let get_ok = function
  | Ok x -> x
  | Error _ -> Alcotest.fail "unexpected Error"

let get_type = function
  | Ok x -> x
  | Error e -> Alcotest.failf "%a" Evm.Types.pp_error e

let uint n = get_type (Evm.Types.Uint256.of_int n)
let chain n = get_type (Evm.Types.Chain_id.of_int n)
let address s = get_type (Evm.Types.Address.of_hex s)

let test_hex_and_address () =
  Alcotest.(check string)
    "quantity zero"
    "0x0"
    (Evm.Types.Uint256.to_quantity Evm.Types.Uint256.zero);
  Alcotest.(check bool)
    "leading zero rejected"
    true
    (Result.is_error (Evm.Types.Uint256.of_quantity "0x00"));
  let a = address "0x52908400098527886e0f7030069857d2e4169ee7" in
  Alcotest.(check string)
    "EIP-55"
    "0x52908400098527886E0F7030069857D2E4169EE7"
    (Evm.Types.Address.to_checksum a);
  Alcotest.(check bool)
    "bad mixed checksum rejected"
    true
    (Result.is_error
       (Evm.Types.Address.of_hex "0x52908400098527886E0F7030069857D2e4169EE7"))

let test_abi () =
  Alcotest.(check string)
    "selector"
    "a9059cbb"
    (Evm.Abi.selector "transfer(address,uint256)" |> Evm.Types.Hex.encode_raw);
  let typ = get_ok (Evm.Abi.ty_of_string "uint256[][2]") in
  Alcotest.(check string)
    "canonical type"
    "uint256[][2]"
    (Evm.Abi.canonical_type typ);
  let tuple = get_ok (Evm.Abi.ty_of_string "(address,(uint256,bool)[])[2]") in
  Alcotest.(check string)
    "tuple arrays"
    "(address,(uint256,bool)[])[2]"
    (Evm.Abi.canonical_type tuple);
  let json =
    Yojson.Safe.from_string
      {|[{"type":"function","name":"balanceOf","inputs":[{"name":"owner","type":"address"}],"outputs":[{"name":"","type":"uint256"}]}]|}
  in
  match get_ok (Evm.Abi.contract_of_yojson json) with
  | [ Evm.Abi.Function f ] ->
      Alcotest.(check string)
        "signature"
        "balanceOf(address)"
        (Evm.Abi.function_signature f.name f.inputs)
  | _ -> Alcotest.fail "unexpected contract ABI"

let typed_data =
  Yojson.Safe.from_string
    {|{
      "types": {
        "EIP712Domain": [
          {"name":"name","type":"string"},
          {"name":"version","type":"string"},
          {"name":"chainId","type":"uint256"},
          {"name":"verifyingContract","type":"address"}
        ],
        "Person": [
          {"name":"name","type":"string"},
          {"name":"wallet","type":"address"}
        ],
        "Mail": [
          {"name":"from","type":"Person"},
          {"name":"to","type":"Person"},
          {"name":"contents","type":"string"}
        ]
      },
      "primaryType":"Mail",
      "domain": {
        "name":"Ether Mail", "version":"1", "chainId":1,
        "verifyingContract":"0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"
      },
      "message": {
        "from":{"name":"Cow","wallet":"0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"},
        "to":{"name":"Bob","wallet":"0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"},
        "contents":"Hello, Bob!"
      }
    }|}

let test_eip712 () =
  let data = get_ok (Evm.Eip712.of_yojson typed_data) in
  let digest = get_ok (Evm.Eip712.digest data) in
  Alcotest.(check string)
    "Ether Mail digest"
    "0xbe609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2"
    (Evm.Types.Hash.to_hex digest)

let private_key () =
  get_ok (Evm.Crypto.private_key_of_bytes (String.make 31 '\000' ^ "\001"))

let test_crypto () =
  let key = private_key () in
  let digest =
    get_type
      (Evm.Types.Hash.of_bytes
         (Digestif.KECCAK_256.digest_string "ocaml-evm"
         |> Digestif.KECCAK_256.to_raw_string))
  in
  let signature =
    get_ok
      (Evm.Crypto.sign_digest
         ~nonce:(String.make 31 '\000' ^ "\002")
         key
         digest)
  in
  Alcotest.(check bool)
    "low-s"
    true
    (Z.leq
       (Evm.Types.Signature.s signature)
       Evm.Types.Signature.half_curve_order);
  let recovered = get_ok (Evm.Crypto.recover digest signature) in
  Alcotest.(check string)
    "recover"
    (Evm.Crypto.public_key_to_bytes (Evm.Crypto.public_key key))
    (Evm.Crypto.public_key_to_bytes recovered);
  Alcotest.(check bool)
    "verify"
    true
    (Evm.Crypto.verify recovered digest signature)

let sample_transactions () =
  let open Evm.Transaction in
  let to_ = address "0x3535353535353535353535353535353535353535" in
  let common_dynamic make =
    make
      ~chain_id:(chain 1)
      ~nonce:(uint 9)
      ~max_priority_fee_per_gas:(uint 2)
      ~max_fee_per_gas:(uint 20)
      ~gas_limit:(uint 21000)
      ~to_
      ~value:(uint 1)
      ~data:""
      ~access_list:[]
  in
  let sig1 =
    get_type (Evm.Types.Signature.make ~y_parity:0 ~r:Z.one ~s:Z.one)
  in
  let auth =
    { chain_id = uint 1; address = to_; nonce = uint 0; signature = sig1 }
  in
  let blob_hash =
    get_type (Evm.Types.Hash.of_bytes ("\001" ^ String.make 31 '\002'))
  in
  [
    Legacy
      {
        nonce = uint 9;
        gas_price = uint 20;
        gas_limit = uint 21000;
        to_ = Call to_;
        value = uint 1;
        data = "";
        chain_id = Some (chain 1);
      };
    Access_list
      {
        chain_id = chain 1;
        nonce = uint 9;
        gas_price = uint 20;
        gas_limit = uint 21000;
        to_ = Call to_;
        value = uint 1;
        data = "";
        access_list = [];
      };
    common_dynamic
      (fun
        ~chain_id
        ~nonce
        ~max_priority_fee_per_gas
        ~max_fee_per_gas
        ~gas_limit
        ~to_
        ~value
        ~data
        ~access_list
      ->
        Dynamic_fee
          {
            chain_id;
            nonce;
            max_priority_fee_per_gas;
            max_fee_per_gas;
            gas_limit;
            to_ = Call to_;
            value;
            data;
            access_list;
          });
    common_dynamic
      (fun
        ~chain_id
        ~nonce
        ~max_priority_fee_per_gas
        ~max_fee_per_gas
        ~gas_limit
        ~to_
        ~value
        ~data
        ~access_list
      ->
        Blob
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
            max_fee_per_blob_gas = uint 3;
            blob_versioned_hashes = [ blob_hash ];
          });
    common_dynamic
      (fun
        ~chain_id
        ~nonce
        ~max_priority_fee_per_gas
        ~max_fee_per_gas
        ~gas_limit
        ~to_
        ~value
        ~data
        ~access_list
      ->
        Set_code
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
            authorization_list = [ auth ];
          });
  ]

let test_transactions () =
  let key = private_key () in
  List.iteri
    (fun i tx ->
      let nonce = String.make 31 '\000' ^ String.make 1 (Char.chr (i + 3)) in
      let signed = get_ok (Evm.Transaction.sign ~nonce key tx) in
      let raw = get_ok (Evm.Transaction.encode_signed signed) in
      let decoded = get_ok (Evm.Transaction.decode_signed raw) in
      Alcotest.(check string)
        (Printf.sprintf "type %d round trip" i)
        raw
        (get_ok (Evm.Transaction.encode_signed decoded));
      let sender = get_ok (Evm.Transaction.sender decoded) in
      Alcotest.(check string)
        "sender"
        (Evm.Types.Address.to_hex
           (Evm.Crypto.address (Evm.Crypto.public_key key)))
        (Evm.Types.Address.to_hex sender))
    (sample_transactions ());
  Alcotest.(check bool)
    "unknown typed envelope rejected"
    true
    (Result.is_error (Evm.Transaction.decode_signed "\x05\xc0"));
  Alcotest.(check bool)
    "leading-zero scalar rejected"
    true
    (Result.is_error
       (Evm.Transaction.decode_signed
          "\xc9\x00\x01\x01\x80\x80\x80\x1b\x01\x01"))

let json_field name = function
  | `Assoc fields -> (
      match List.assoc_opt name fields with
      | Some value -> value
      | None -> Alcotest.failf "fixture is missing %s" name)
  | _ -> Alcotest.fail "fixture entry must be an object"

let json_string name json =
  match json_field name json with
  | `String value -> value
  | _ -> Alcotest.failf "fixture field %s must be a string" name

let json_list name json =
  match json_field name json with
  | `List values -> values
  | _ -> Alcotest.failf "fixture field %s must be an array" name

let optional_field name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let transaction_kind = function
  | Evm.Transaction.Legacy _ -> "legacy"
  | Access_list _ -> "type1"
  | Dynamic_fee _ -> "type2"
  | Blob _ -> "type3"
  | Set_code _ -> "type4"

let test_transaction_fixtures () =
  let fixture_path =
    let from_root = "test/fixtures/transaction_vectors.json" in
    if Sys.file_exists from_root then from_root
    else "fixtures/transaction_vectors.json"
  in
  let fixtures = Yojson.Safe.from_file fixture_path in
  List.iter
    (fun fixture ->
      let name = json_string "name" fixture in
      let raw_hex = json_string "raw" fixture in
      let raw = Evm.Types.Hex.decode raw_hex |> get_type in
      let signed =
        match Evm.Transaction.decode_signed raw with
        | Ok signed -> signed
        | Error error -> Alcotest.failf "%s: %s" name error
      in
      Alcotest.(check string)
        (name ^ " kind")
        (json_string "kind" fixture)
        (transaction_kind signed.transaction);
      Alcotest.(check string)
        (name ^ " round trip")
        raw
        (get_ok (Evm.Transaction.encode_signed signed));
      (match optional_field "hash" fixture with
      | None -> ()
      | Some (`String expected) ->
          Alcotest.(check string)
            (name ^ " hash")
            expected
            (get_ok (Evm.Transaction.hash signed) |> Evm.Types.Hash.to_hex)
      | Some _ -> Alcotest.failf "%s hash must be a string" name);
      (match optional_field "sender" fixture with
      | None -> ()
      | Some (`String expected) ->
          Alcotest.(check string)
            (name ^ " sender")
            expected
            (get_ok (Evm.Transaction.sender signed) |> Evm.Types.Address.to_hex)
      | Some _ -> Alcotest.failf "%s sender must be a string" name);
      match optional_field "signingHash" fixture with
      | None -> ()
      | Some (`String expected) ->
          Alcotest.(check string)
            (name ^ " signing hash")
            expected
            (get_ok (Evm.Transaction.signing_hash signed.transaction)
            |> Evm.Types.Hash.to_hex)
      | Some _ -> Alcotest.failf "%s signingHash must be a string" name)
    (json_list "valid" fixtures);
  List.iter
    (fun fixture ->
      let name = json_string "name" fixture in
      let raw = json_string "raw" fixture |> Evm.Types.Hex.decode |> get_type in
      Alcotest.(check bool)
        name
        true
        (Result.is_error (Evm.Transaction.decode_signed raw)))
    (json_list "invalid" fixtures)

let test_allocation_limits () =
  let abi_limits =
    {
      Evm.Abi.max_input_bytes = 96;
      max_dynamic_bytes = 8;
      max_nesting = 3;
      max_elements = 2;
      max_contract_items = 1;
      max_string_bytes = 32;
    }
  in
  let dynamic =
    Evm.Abi.encode [ Evm.Abi.Bytes (String.make 9 'x') ] |> get_ok
  in
  Alcotest.(check bool)
    "ABI dynamic byte budget"
    true
    (Result.is_error
       (Evm.Abi.decode_with_limits abi_limits [ Evm.Abi.TBytes ] dynamic));
  Alcotest.(check bool)
    "ABI type nesting budget"
    true
    (Result.is_error
       (Evm.Abi.ty_of_string_with_limits abi_limits "uint256[][][][]"));
  Alcotest.(check bool)
    "ABI element budget"
    true
    (Result.is_error
       (Evm.Abi.decode_with_limits
          abi_limits
          [ Evm.Abi.TFixedArray (Evm.Abi.TUint 256, 3) ]
          (String.make 96 '\000')));
  let abi_item =
    `Assoc
      [
        ("type", `String "function"); ("name", `String "f"); ("inputs", `List []);
      ]
  in
  Alcotest.(check bool)
    "ABI contract item budget"
    true
    (Result.is_error
       (Evm.Abi.contract_of_yojson_with_limits
          abi_limits
          (`List [ abi_item; abi_item ])));
  Alcotest.(check bool)
    "ABI raw JSON byte budget"
    true
    (Result.is_error
       (Evm.Abi.contract_of_json_string_with_limits
          abi_limits
          (String.make 97 'x')));
  let eip_limits =
    {
      Evm.Eip712.max_input_bytes = 256;
      max_json_depth = 3;
      max_json_nodes = 32;
      max_array_length = 2;
      max_object_fields = 4;
      max_string_bytes = 16;
      max_types = 2;
      max_members_per_type = 2;
      max_identifier_bytes = 16;
    }
  in
  let too_deep = `List [ `List [ `List [ `List [ `Null ] ] ] ] in
  Alcotest.(check bool)
    "EIP-712 JSON depth budget"
    true
    (Result.is_error (Evm.Eip712.of_yojson_with_limits eip_limits too_deep));
  let too_wide = `List [ `Null; `Null; `Null ] in
  Alcotest.(check bool)
    "EIP-712 JSON array budget"
    true
    (Result.is_error (Evm.Eip712.of_yojson_with_limits eip_limits too_wide));
  Alcotest.(check bool)
    "EIP-712 raw JSON byte budget"
    true
    (Result.is_error
       (Evm.Eip712.of_json_string_with_limits eip_limits (String.make 257 'x')));
  let parsed = get_ok (Evm.Eip712.of_yojson typed_data) in
  let parsed_from_string =
    Yojson.Safe.to_string typed_data |> Evm.Eip712.of_json_string |> get_ok
  in
  Alcotest.(check string)
    "bounded string parser preserves digest"
    (get_ok (Evm.Eip712.digest parsed) |> Evm.Types.Hash.to_hex)
    (get_ok (Evm.Eip712.digest parsed_from_string) |> Evm.Types.Hash.to_hex);
  let strict_string_limits =
    { Evm.Eip712.default_limits with max_string_bytes = 4 }
  in
  Alcotest.(check bool)
    "EIP-712 digest revalidates manually accessible data"
    true
    (Result.is_error
       (Evm.Eip712.digest_with_limits strict_string_limits parsed))

let prop_quantity_roundtrip =
  QCheck2.Test.make
    ~count:5_000
    ~name:"uint256 quantity encode/decode round trip"
    QCheck2.Gen.(int_range 0 max_int)
    (fun n ->
      let value = Evm.Types.Uint256.of_int n |> Result.get_ok in
      match
        Evm.Types.Uint256.of_quantity (Evm.Types.Uint256.to_quantity value)
      with
      | Ok decoded -> Evm.Types.Uint256.equal value decoded
      | Error _ -> false)

let prop_transaction_decoder_total =
  QCheck2.Test.make
    ~count:10_000
    ~name:"transaction decoder never raises"
    QCheck2.Gen.(string_size (int_bound 512))
    (fun bytes ->
      try
        ignore (Evm.Transaction.decode_signed bytes);
        true
      with _ -> false)

let prop_bounded_json_decoders_total =
  QCheck2.Test.make
    ~count:10_000
    ~name:"bounded ABI/EIP-712 JSON decoders never raise"
    QCheck2.Gen.(string_size (int_bound 2048))
    (fun input ->
      try
        ignore (Evm.Abi.contract_of_json_string input);
        ignore (Evm.Eip712.of_json_string input);
        ignore (Evm.Abi.ty_of_string input);
        true
      with _ -> false)

let () =
  Alcotest.run
    "ocaml-evm"
    [
      ( "types",
        [ Alcotest.test_case "hex and address" `Quick test_hex_and_address ] );
      ("abi", [ Alcotest.test_case "types and JSON" `Quick test_abi ]);
      ("eip712", [ Alcotest.test_case "Ether Mail vector" `Quick test_eip712 ]);
      ("crypto", [ Alcotest.test_case "sign/recover" `Quick test_crypto ]);
      ( "transaction",
        [
          Alcotest.test_case "types 0-4" `Quick test_transactions;
          Alcotest.test_case
            "independent fixtures"
            `Quick
            test_transaction_fixtures;
        ] );
      ( "limits",
        [
          Alcotest.test_case "allocation budgets" `Quick test_allocation_limits;
        ] );
      ( "properties",
        List.map
          QCheck_alcotest.to_alcotest
          [
            prop_quantity_roundtrip;
            prop_transaction_decoder_total;
            prop_bounded_json_decoders_total;
          ] );
    ]
