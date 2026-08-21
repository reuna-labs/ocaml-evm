module Transport = struct
  type t = { mutable incoming : string list; mutable sent : string list }
  type connection = t
  type 'a io = 'a

  let return x = x
  let bind x f = f x
  let connect t = Ok t

  let send_text t body =
    t.sent <- body :: t.sent;
    Ok ()

  let receive_text t =
    match t.incoming with
    | [] -> Error "closed"
    | body :: rest ->
        t.incoming <- rest;
        Ok body

  let close _ = ()
end

module Driver = Evm_rpc_websocket.Make (Transport)

let hash byte =
  Evm_types.Hash.of_bytes (String.make 32 byte)
  |> Result.get_ok |> Evm_types.Hash.to_hex

let test_driver () =
  let response = {|{"jsonrpc":"2.0","id":1,"result":"sub-7"}|} in
  let notification =
    Printf.sprintf
      {|{"jsonrpc":"2.0","method":"eth_subscription","params":{"subscription":"sub-7","result":{"number":"0x2","hash":"%s","parentHash":"%s"}}}|}
      (hash '\002')
      (hash '\001')
  in
  let transport =
    Transport.{ incoming = [ response; notification ]; sent = [] }
  in
  let driver = Driver.create transport Evm_rpc.Subscription.New_heads in
  (match Driver.connect driver with
  | Ok () -> ()
  | Error message -> Alcotest.fail message);
  Alcotest.(check int) "subscribe sent" 1 (List.length transport.sent);
  Alcotest.(check bool)
    "head delivered"
    true
    (match Driver.next driver with
    | Driver.Notification (Evm_rpc.Subscription.New_head head) ->
        Z.equal (Evm_types.Uint256.to_z head.number) (Z.of_int 2)
    | _ -> false);
  Alcotest.(check bool)
    "reconnect surfaced"
    true
    (match Driver.next driver with
    | Driver.Reconnect_required "closed" -> true
    | _ -> false);
  Alcotest.(check int) "generation incremented" 1 (Driver.generation driver)

let test_limit () =
  let transport =
    Transport.
      {
        incoming = [ {|{"jsonrpc":"2.0","id":1,"result":"sub-7"}|} ];
        sent = [];
      }
  in
  let driver =
    Driver.create ~max_message_bytes:8 transport Evm_rpc.Subscription.New_heads
  in
  Alcotest.(check bool)
    "oversize rejected"
    true
    (match Driver.connect driver with
    | Error "WebSocket response exceeds configured limit" -> true
    | _ -> false)

let () =
  Alcotest.run
    "ocaml-evm-rpc-websocket"
    [
      ( "driver",
        [
          Alcotest.test_case "subscribe and reconnect" `Quick test_driver;
          Alcotest.test_case "message limit" `Quick test_limit;
        ] );
    ]
