open Lwt.Syntax

let max_forwarded_bytes = 16 * 1024 * 1024

let bounded_body body =
  let stream = Cohttp_lwt.Body.to_stream body in
  let buffer = Buffer.create 4096 in
  let rec loop total =
    let* chunk = Lwt_stream.get stream in
    match chunk with
    | None -> Lwt.return (Ok (Buffer.contents buffer))
    | Some chunk ->
        let total = total + String.length chunk in
        if total > max_forwarded_bytes then
          Lwt.return (Error "upstream response exceeded proxy limit")
        else (
          Buffer.add_string buffer chunk;
          loop total)
  in
  loop 0

let respond ?(status = `OK) body =
  Cohttp_lwt_unix.Server.respond_string ~status ~body ()

let inject = function
  | "malformed" -> Some (respond {|{"jsonrpc":|})
  | "id-mismatch" ->
      Some (respond {|{"jsonrpc":"2.0","id":999,"result":"0x539"}|})
  | "rpc-error" ->
      Some
        (respond
           {|{"jsonrpc":"2.0","id":0,"error":{"code":-32099,"message":"injected by ocaml-evm"}}|})
  | "conflicting" ->
      Some
        (respond
           {|{"jsonrpc":"2.0","id":0,"result":"0x539","error":{"code":-32099,"message":"injected"}}|})
  | "oversized" -> Some (respond (String.make (17 * 1024 * 1024) 'x'))
  | "http-500" -> Some (respond ~status:`Internal_server_error "injected")
  | _ -> None

let forward upstream request body =
  let* body = Cohttp_lwt.Body.to_string body in
  let headers = Cohttp.Request.headers request in
  let* response, response_body =
    Cohttp_lwt_unix.Client.post
      ~headers
      ~body:(Cohttp_lwt.Body.of_string body)
      upstream
  in
  let* bounded = bounded_body response_body in
  match bounded with
  | Error message -> respond ~status:`Bad_gateway message
  | Ok body ->
      Cohttp_lwt_unix.Server.respond_string
        ~status:(Cohttp.Response.status response)
        ~headers:(Cohttp.Response.headers response)
        ~body
        ()

let run ~listen ~upstream =
  let callback _connection request body =
    let fault =
      Http.Header.get (Cohttp.Request.headers request) "x-ocaml-evm-fault"
    in
    match Option.bind fault inject with
    | Some response -> response
    | None -> forward upstream request body
  in
  Printf.printf
    "ocaml-evm fault proxy listening on 127.0.0.1:%d -> %s\n%!"
    listen
    (Uri.to_string upstream);
  Cohttp_lwt_unix.Server.create
    ~mode:(`TCP (`Port listen))
    (Cohttp_lwt_unix.Server.make ~callback ())

let () =
  let listen = ref 38545 and upstream = ref None in
  Arg.parse
    [
      ("--listen", Arg.Set_int listen, "local TCP port (default 38545)");
      ("--upstream", Arg.String (fun value -> upstream := Some value), "RPC URL");
    ]
    (fun _ -> ())
    "ocaml-evm fault proxy";
  match !upstream with
  | None ->
      Printf.eprintf "--upstream is required\n%!";
      exit 2
  | Some upstream ->
      Lwt_main.run (run ~listen:!listen ~upstream:(Uri.of_string upstream))
