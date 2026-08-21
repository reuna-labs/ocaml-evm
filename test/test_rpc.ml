let get_ok = function
  | Ok value -> value
  | Error _ -> Alcotest.fail "unexpected Error"

let uint n = Evm_types.Uint256.of_int n |> get_ok
let address byte = Evm_types.Address.of_bytes (String.make 20 byte) |> get_ok
let hash byte = Evm_types.Hash.of_bytes (String.make 32 byte) |> get_ok

let test_codec () =
  let method_ = Evm_rpc.Methods.chain_id in
  let request = Evm_rpc.Codec.request_string ~id:(Evm_rpc.Id.Int 7) method_ in
  Alcotest.(check string)
    "request"
    {|{"jsonrpc":"2.0","id":7,"method":"eth_chainId","params":[]}|}
    request;
  let chain =
    Evm_rpc.Codec.decode_response
      ~id:(Evm_rpc.Id.Int 7)
      method_
      {|{"jsonrpc":"2.0","id":7,"result":"0x1"}|}
    |> get_ok
  in
  Alcotest.(check string)
    "chain ID"
    "1"
    (Z.to_string (Evm_types.Chain_id.to_z chain));
  let mismatch =
    Evm_rpc.Codec.decode_response
      ~id:(Evm_rpc.Id.Int 7)
      method_
      {|{"jsonrpc":"2.0","id":8,"result":"0x1"}|}
  in
  Alcotest.(check bool)
    "ID mismatch"
    true
    (match mismatch with
    | Error (Evm_rpc.Error.Id_mismatch _) -> true
    | _ -> false);
  let rpc_error =
    Evm_rpc.Codec.decode_response
      ~id:(Evm_rpc.Id.Int 7)
      method_
      {|{"jsonrpc":"2.0","id":7,"error":{"code":-32000,"message":"denied"}}|}
  in
  Alcotest.(check bool)
    "RPC error"
    true
    (match rpc_error with
    | Error (Evm_rpc.Error.Rpc { code = -32000; _ }) -> true
    | _ -> false)

let test_provider_mock () =
  let mock =
    Evm_rpc.Mock.create
      [
        {
          Evm_rpc.Mock.method_ = "eth_chainId";
          params = [];
          response = Return (`String "0xaa36a7");
        };
      ]
  in
  let module Client = Evm_rpc.Provider.Make (Evm_rpc.Mock.Provider) in
  let chain = Client.call mock Evm_rpc.Methods.chain_id |> get_ok in
  Alcotest.(check string)
    "Sepolia"
    "11155111"
    (Z.to_string (Evm_types.Chain_id.to_z chain));
  Alcotest.(check int) "expectations consumed" 0 (Evm_rpc.Mock.remaining mock)

let test_parameters () =
  let request =
    Evm_rpc.Types.transaction_request
      ~from:(address '\001')
      ~to_:(address '\002')
      ~value:(uint 16)
      ~data:"\xde\xad"
      ()
  in
  let json = Evm_rpc.Types.transaction_request_to_yojson request in
  Alcotest.(check string)
    "call object"
    {|{"from":"0x0101010101010101010101010101010101010101","to":"0x0202020202020202020202020202020202020202","value":"0x10","data":"0xdead"}|}
    (Yojson.Safe.to_string json);
  Alcotest.(check bool)
    "mutually exclusive filter blocks"
    true
    (Result.is_error
       (Evm_rpc.Types.log_filter
          ~from_block:(`Tag Latest)
          ~block_hash:(hash '\003')
          ()))

let test_fee_history () =
  let json =
    Yojson.Safe.from_string
      {|{
        "oldestBlock":"0x10",
        "baseFeePerGas":["0x1","0x2"],
        "gasUsedRatio":[0.5],
        "reward":[["0x3"]],
        "baseFeePerBlobGas":["0x4","0x5"],
        "blobGasUsedRatio":[0.25]
      }|}
  in
  let history = Evm_rpc.Types.fee_history_of_yojson json |> get_ok in
  Alcotest.(check int) "base fees" 2 (List.length history.base_fee_per_gas);
  Alcotest.(check bool)
    "invalid percentile order"
    true
    (Result.is_error
       (Evm_rpc.Methods.fee_history
          ~block_count:(uint 2)
          ~newest_block:(`Tag Latest)
          ~reward_percentiles:[ 90.; 10. ]
          ()));
  Alcotest.(check bool)
    "block-count cap"
    true
    (Result.is_error
       (Evm_rpc.Methods.fee_history
          ~block_count:(uint 1025)
          ~newest_block:(`Tag Latest)
          ()))

let test_revert () =
  let body = Evm_abi.encode [ Evm_abi.String "policy denied" ] |> get_ok in
  let raw = Evm_abi.selector "Error(string)" ^ body in
  let rpc =
    Evm_rpc.Error.
      {
        code = -32000;
        message = "execution reverted";
        data = Some (`String (Evm_types.Hex.encode raw));
      }
  in
  Alcotest.(check bool)
    "Error(string)"
    true
    (match Evm_rpc.Revert.of_rpc_error rpc with
    | Some (Evm_rpc.Revert.Error_string "policy denied") -> true
    | _ -> false)

let head number hash_byte parent_byte =
  Evm_rpc.Subscription.
    {
      number = uint number;
      hash = hash hash_byte;
      parent_hash = hash parent_byte;
    }

let test_heads_and_reconnect () =
  let tracker = Evm_rpc.Subscription.Head_tracker.create ~capacity:8 () in
  let h1 = head 1 '\001' '\000' in
  let h2a = head 2 '\002' '\001' in
  let h3a = head 3 '\003' '\002' in
  let h2b = head 2 '\012' '\001' in
  ignore (Evm_rpc.Subscription.Head_tracker.observe tracker h1);
  ignore (Evm_rpc.Subscription.Head_tracker.observe tracker h2a);
  ignore (Evm_rpc.Subscription.Head_tracker.observe tracker h3a);
  let update = Evm_rpc.Subscription.Head_tracker.observe tracker h2b in
  Alcotest.(check bool)
    "two-block reorg"
    true
    (match update with
    | Evm_rpc.Subscription.Reorg { removed = [ a; b ]; added = [ c ] } ->
        Evm_types.Hash.equal a.hash h3a.hash
        && Evm_types.Hash.equal b.hash h2a.hash
        && Evm_types.Hash.equal c.hash h2b.hash
    | _ -> false);
  let session = Evm_rpc.Subscription.Reconnect.create New_heads in
  Alcotest.(check bool)
    "connect action"
    true
    (match Evm_rpc.Subscription.Reconnect.start session with
    | Connect -> true
    | _ -> false);
  let subscribe =
    Evm_rpc.Subscription.Reconnect.connected ~id:(Evm_rpc.Id.Int 1) session
    |> get_ok
  in
  Alcotest.(check bool)
    "subscribe action"
    true
    (match subscribe with
    | Send_subscribe _ -> true
    | _ -> false);
  ignore (Evm_rpc.Subscription.Reconnect.subscribed session "sub-1" |> get_ok);
  ignore (Evm_rpc.Subscription.Reconnect.disconnected session);
  Alcotest.(check int)
    "generation"
    1
    (Evm_rpc.Subscription.Reconnect.generation session)

let prop_response_decoder_total =
  QCheck2.Test.make
    ~count:10_000
    ~name:"JSON-RPC response decoder never raises"
    QCheck2.Gen.(string_size (int_bound 1024))
    (fun body ->
      try
        ignore
          (Evm_rpc.Codec.decode_response
             ~id:(Evm_rpc.Id.Int 0)
             Evm_rpc.Methods.chain_id
             body);
        true
      with _ -> false)

let () =
  Alcotest.run
    "ocaml-evm-rpc"
    [
      ( "rpc",
        [
          Alcotest.test_case "codec" `Quick test_codec;
          Alcotest.test_case "provider mock" `Quick test_provider_mock;
          Alcotest.test_case "parameters" `Quick test_parameters;
          Alcotest.test_case "fee history" `Quick test_fee_history;
          Alcotest.test_case "revert" `Quick test_revert;
          Alcotest.test_case
            "heads and reconnect"
            `Quick
            test_heads_and_reconnect;
        ] );
      ( "properties",
        List.map QCheck_alcotest.to_alcotest [ prop_response_decoder_total ] );
    ]
