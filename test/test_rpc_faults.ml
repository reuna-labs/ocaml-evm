open Lwt.Syntax
open Lwt.Infix

let response ?(status = `OK) body =
  Cohttp_lwt_unix.Server.respond_string ~status ~body ()

let callback _connection request _body =
  let fault =
    Cohttp.Request.headers request |> fun headers ->
    Http.Header.get headers "x-ocaml-evm-fault"
  in
  match fault with
  | None -> response {|{"jsonrpc":"2.0","id":0,"result":"0x539"}|}
  | Some "malformed" -> response {|{"jsonrpc":|}
  | Some "id-mismatch" ->
      response {|{"jsonrpc":"2.0","id":99,"result":"0x539"}|}
  | Some "rpc-error" ->
      response
        {|{"jsonrpc":"2.0","id":0,"error":{"code":-32001,"message":"injected"}}|}
  | Some "conflicting" ->
      response
        {|{"jsonrpc":"2.0","id":0,"result":"0x539","error":{"code":-32001,"message":"injected"}}|}
  | Some "decode" -> response {|{"jsonrpc":"2.0","id":0,"result":"0x00"}|}
  | Some "oversized" -> response (String.make 4096 'x')
  | Some "http-500" -> response ~status:`Internal_server_error "injected"
  | Some other -> response ~status:`Bad_request ("unknown fault: " ^ other)

let with_server f =
  let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Lwt_unix.setsockopt socket Unix.SO_REUSEADDR true;
  let* () =
    Lwt_unix.bind socket (Unix.ADDR_INET (Unix.inet_addr_loopback, 0))
  in
  Lwt_unix.listen socket 16;
  let port =
    match Lwt_unix.getsockname socket with
    | Unix.ADDR_INET (_, port) -> port
    | Unix.ADDR_UNIX _ -> assert false
  in
  let stop, stop_wakener = Lwt.wait () in
  let server =
    Cohttp_lwt_unix.Server.create
      ~stop
      ~mode:(`TCP (`Socket socket))
      (Cohttp_lwt_unix.Server.make ~callback ())
  in
  Lwt.finalize
    (fun () -> Lwt.pick [ server; f port ])
    (fun () ->
      Lwt.wakeup_later stop_wakener ();
      Lwt.return_unit)

let client ?fault ?(max_response_bytes = 1024) port =
  let headers =
    match fault with
    | None -> Http.Header.init ()
    | Some fault -> Http.Header.init_with "x-ocaml-evm-fault" fault
  in
  Evm_rpc_unix.create
    ~headers
    ~max_response_bytes
    (Uri.of_string (Printf.sprintf "http://127.0.0.1:%d" port))

let call ?fault ?max_response_bytes port =
  Evm_rpc_unix.Client.call
    (client ?fault ?max_response_bytes port)
    Evm_rpc.Methods.chain_id

let check_error label predicate = function
  | Error error when predicate error -> Lwt.return_unit
  | Error error ->
      Alcotest.failf
        "%s returned the wrong error: %a"
        label
        Evm_rpc.Error.pp
        error
  | Ok _ -> Alcotest.failf "%s unexpectedly succeeded" label

let test_faults () =
  Lwt_main.run
    (with_server (fun port ->
         let* normal = call port in
         (match normal with
         | Ok chain_id ->
             Alcotest.(check string)
               "normal response"
               "1337"
               (Evm_types.Chain_id.to_z chain_id |> Z.to_string)
         | Error error -> Alcotest.failf "%a" Evm_rpc.Error.pp error);
         let* () =
           call ~fault:"malformed" port
           >>= check_error "malformed" (function
                 | Evm_rpc.Error.Malformed_json _ -> true
                 | _ -> false)
         in
         let* () =
           call ~fault:"id-mismatch" port
           >>= check_error "ID mismatch" (function
                 | Evm_rpc.Error.Id_mismatch _ -> true
                 | _ -> false)
         in
         let* () =
           call ~fault:"rpc-error" port
           >>= check_error "RPC error" (function
                 | Evm_rpc.Error.Rpc { code = -32001; _ } -> true
                 | _ -> false)
         in
         let* () =
           call ~fault:"conflicting" port
           >>= check_error "conflicting result/error" (function
                 | Evm_rpc.Error.Invalid_response _ -> true
                 | _ -> false)
         in
         let* () =
           call ~fault:"decode" port
           >>= check_error "invalid result" (function
                 | Evm_rpc.Error.Decode _ -> true
                 | _ -> false)
         in
         let* () =
           call ~fault:"http-500" port
           >>= check_error "HTTP 500" (function
                 | Evm_rpc.Error.Transport _ -> true
                 | _ -> false)
         in
         call ~fault:"oversized" ~max_response_bytes:64 port
         >>= check_error "oversized response" (function
               | Evm_rpc.Error.Transport message ->
                   String.starts_with
                     ~prefix:"response exceeds 64 bytes"
                     message
               | _ -> false)))

let () =
  Alcotest.run
    "ocaml-evm-rpc-faults"
    [
      ( "fault injection",
        [ Alcotest.test_case "HTTP and JSON-RPC failures" `Quick test_faults ]
      );
    ]
