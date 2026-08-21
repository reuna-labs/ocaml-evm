module Make (C : Cohttp_lwt.S.Client) = struct
  type t = {
    ctx : C.ctx option;
    headers : Http.Header.t;
    uri : Uri.t;
    max_response_bytes : int;
  }

  let create ?ctx ?(headers = Http.Header.init ())
      ?(max_response_bytes = 16 * 1024 * 1024) uri =
    if max_response_bytes <= 0 then
      invalid_arg "max_response_bytes must be positive";
    let headers =
      Http.Header.add_unless_exists headers "content-type" "application/json"
    in
    { ctx; headers; uri; max_response_bytes }

  let uri t = t.uri

  module Http_transport = struct
    type nonrec t = t
    type 'a io = 'a Lwt.t

    let return = Lwt.return
    let bind = Lwt.bind

    let body_to_string ~max_bytes body =
      let stream = Cohttp_lwt.Body.to_stream body in
      let buffer = Buffer.create (min max_bytes 4096) in
      let rec loop total =
        Lwt.bind (Lwt_stream.get stream) (function
          | None -> Lwt.return (Ok (Buffer.contents buffer))
          | Some chunk ->
              let total = total + String.length chunk in
              if total > max_bytes then
                Lwt.bind (Cohttp_lwt.Body.drain_body body) (fun () ->
                    Lwt.return
                      (Error
                         (Printf.sprintf "response exceeds %d bytes" max_bytes)))
              else (
                Buffer.add_string buffer chunk;
                loop total))
      in
      loop 0

    let post t ~body =
      Lwt.catch
        (fun () ->
          Lwt.bind
            (C.post
               ?ctx:t.ctx
               ~headers:t.headers
               ~body:(Cohttp_lwt.Body.of_string body)
               t.uri)
            (fun (response, response_body) ->
              Lwt.bind
                (body_to_string ~max_bytes:t.max_response_bytes response_body)
                (function
                | Error _ as error -> Lwt.return error
                | Ok response_body ->
                    let status =
                      Http.Response.status response |> Http.Status.to_int
                    in
                    if status >= 200 && status < 300 then
                      Lwt.return (Ok response_body)
                    else
                      Lwt.return
                        (Error
                           (Printf.sprintf
                              "HTTP %d from %s: %s"
                              status
                              (Uri.to_string t.uri)
                              response_body)))))
        (fun exn -> Lwt.return (Error (Printexc.to_string exn)))
  end

  module Provider = Evm_rpc.Provider.Of_http (Http_transport)
  module Client = Evm_rpc.Provider.Make (Provider)
end
