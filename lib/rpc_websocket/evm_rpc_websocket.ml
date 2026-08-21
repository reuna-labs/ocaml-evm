module type TRANSPORT = sig
  type t
  type connection
  type 'a io

  val return : 'a -> 'a io
  val bind : 'a io -> ('a -> 'b io) -> 'b io
  val connect : t -> (connection, string) result io
  val send_text : connection -> string -> (unit, string) result io
  val receive_text : connection -> (string, string) result io
  val close : connection -> unit io
end

module Make (T : TRANSPORT) = struct
  type t = {
    transport : T.t;
    kind : Evm_rpc.Subscription.kind;
    session : Evm_rpc.Subscription.Reconnect.t;
    mutable connection : T.connection option;
    mutable next_id : int;
    max_message_bytes : int;
  }

  type event =
    | Notification of Evm_rpc.Subscription.notification
    | Ignored
    | Reconnect_required of string

  let create ?(max_message_bytes = 16 * 1024 * 1024) transport kind =
    if max_message_bytes <= 0 then
      invalid_arg "max_message_bytes must be positive";
    {
      transport;
      kind;
      session = Evm_rpc.Subscription.Reconnect.create kind;
      connection = None;
      next_id = 1;
      max_message_bytes;
    }

  let generation t = Evm_rpc.Subscription.Reconnect.generation t.session

  let connect t =
    (match Evm_rpc.Subscription.Reconnect.state t.session with
    | Disconnected -> ignore (Evm_rpc.Subscription.Reconnect.start t.session)
    | Connecting -> ()
    | Subscribing | Active _ -> ());
    T.bind (T.connect t.transport) (function
      | Error _ as error -> T.return error
      | Ok connection -> (
          t.connection <- Some connection;
          let id = Evm_rpc.Id.Int t.next_id in
          t.next_id <- t.next_id + 1;
          match Evm_rpc.Subscription.Reconnect.connected ~id t.session with
          | Error _ as error -> T.return error
          | Ok (Send_subscribe request) ->
              T.bind
                (T.send_text connection (Yojson.Safe.to_string request))
                (function
                  | Error _ as error -> T.return error
                  | Ok () ->
                      T.bind (T.receive_text connection) (function
                        | Error _ as error -> T.return error
                        | Ok response
                          when String.length response > t.max_message_bytes ->
                            T.return
                              (Error
                                 "WebSocket response exceeds configured limit")
                        | Ok response -> (
                            match
                              Evm_rpc.Codec.decode_response
                                ~id
                                (Evm_rpc.Subscription.subscribe t.kind)
                                response
                            with
                            | Error error ->
                                T.return
                                  (Error
                                     (Format.asprintf
                                        "%a"
                                        Evm_rpc.Error.pp
                                        error))
                            | Ok subscription_id -> (
                                match
                                  Evm_rpc.Subscription.Reconnect.subscribed
                                    t.session
                                    subscription_id
                                with
                                | Ok Ready -> T.return (Ok ())
                                | Ok (Connect | Send_subscribe _ | Ignore) ->
                                    T.return (Error "invalid reconnect action")
                                | Error _ as error -> T.return error))))
          | Ok (Connect | Ready | Ignore) ->
              T.return (Error "invalid reconnect action")))

  let next t =
    match t.connection with
    | None -> T.return (Reconnect_required "WebSocket is not connected")
    | Some connection ->
        T.bind (T.receive_text connection) (function
          | Error message ->
              ignore (Evm_rpc.Subscription.Reconnect.disconnected t.session);
              t.connection <- None;
              T.return (Reconnect_required message)
          | Ok body when String.length body > t.max_message_bytes ->
              T.return
                (Reconnect_required "WebSocket message exceeds configured limit")
          | Ok body -> (
              try
                match
                  Evm_rpc.Subscription.Reconnect.notification
                    t.session
                    (Yojson.Safe.from_string body)
                with
                | Ok None -> T.return Ignored
                | Ok (Some notification) -> T.return (Notification notification)
                | Error message -> T.return (Reconnect_required message)
              with Yojson.Json_error message ->
                T.return
                  (Reconnect_required ("malformed WebSocket JSON: " ^ message))))

  let disconnect t =
    ignore (Evm_rpc.Subscription.Reconnect.disconnected t.session);
    match t.connection with
    | None -> T.return ()
    | Some connection ->
        t.connection <- None;
        T.close connection
end
