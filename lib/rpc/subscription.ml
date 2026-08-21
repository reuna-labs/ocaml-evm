type head = {
  number : Evm_types.Uint256.t;
  hash : Evm_types.Hash.t;
  parent_hash : Evm_types.Hash.t;
}

type head_update =
  | Applied of head
  | Reorg of { removed : head list; added : head list }
  | Duplicate of head
  | Need_resync of { previous : head option; incoming : head }

module Head_tracker = struct
  type t = { capacity : int; mutable history : head list }

  let create ?(capacity = 64) () =
    if capacity <= 0 then invalid_arg "head tracker capacity must be positive";
    { capacity; history = [] }

  let tip t =
    match t.history with
    | [] -> None
    | head :: _ -> Some head

  let history t = t.history

  let trim capacity values =
    let rec loop n acc = function
      | [] -> List.rev acc
      | _ when n = 0 -> List.rev acc
      | value :: rest -> loop (n - 1) (value :: acc) rest
    in
    loop capacity [] values

  let reset t history =
    let rec linked = function
      | [] | [ _ ] -> true
      | newer :: (older :: _ as rest) ->
          Evm_types.Hash.equal newer.parent_hash older.hash && linked rest
    in
    if not (linked history) then Error "head history is not a linked chain"
    else (
      t.history <- trim t.capacity history;
      Ok ())

  let observe t incoming =
    match t.history with
    | [] ->
        t.history <- [ incoming ];
        Applied incoming
    | current :: _ when Evm_types.Hash.equal current.hash incoming.hash ->
        Duplicate incoming
    | current :: _ when Evm_types.Hash.equal current.hash incoming.parent_hash
      ->
        t.history <- trim t.capacity (incoming :: t.history);
        Applied incoming
    | current :: _ -> (
        let rec split removed = function
          | [] -> None
          | ancestor :: rest ->
              if Evm_types.Hash.equal ancestor.hash incoming.parent_hash then
                Some (List.rev removed, ancestor :: rest)
              else split (ancestor :: removed) rest
        in
        match split [] t.history with
        | Some (removed, retained) ->
            t.history <- trim t.capacity (incoming :: retained);
            Reorg { removed; added = [ incoming ] }
        | None -> Need_resync { previous = Some current; incoming })
end

type kind = New_heads | Logs of Types.log_filter
type notification = New_head of head | Log of Types.log

let ( >>= ) = Result.bind

let string = function
  | `String value -> Ok value
  | _ -> Error "expected a string"

let decode_hash = function
  | `String value ->
      Evm_types.Hash.of_hex value
      |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)
  | _ -> Error "expected a hash string"

let quantity = function
  | `String value ->
      Evm_types.Uint256.of_quantity value
      |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)
  | _ -> Error "expected a quantity string"

let head_of_yojson = function
  | `Assoc fields -> (
      match
        ( List.assoc_opt "number" fields,
          List.assoc_opt "hash" fields,
          List.assoc_opt "parentHash" fields )
      with
      | Some number, Some hash_value, Some parent_hash ->
          quantity number >>= fun number ->
          decode_hash hash_value >>= fun hash ->
          decode_hash parent_hash >>= fun parent_hash ->
          Ok { number; hash; parent_hash }
      | _ ->
          Error "newHeads notification is missing number, hash, or parentHash")
  | _ -> Error "newHeads result must be an object"

let subscribe = function
  | New_heads ->
      Method.make ~name:"eth_subscribe" ~params:[ `String "newHeads" ] string
  | Logs filter ->
      Method.make
        ~name:"eth_subscribe"
        ~params:[ `String "logs"; Types.log_filter_to_yojson filter ]
        string

let unsubscribe subscription_id =
  Method.make
    ~name:"eth_unsubscribe"
    ~params:[ `String subscription_id ]
    (function
      | `Bool value -> Ok value
      | _ -> Error "expected a boolean")

let notification_of_yojson ~subscription_id kind = function
  | `Assoc fields -> (
      match
        ( List.assoc_opt "jsonrpc" fields,
          List.assoc_opt "method" fields,
          List.assoc_opt "params" fields )
      with
      | ( Some (`String "2.0"),
          Some (`String "eth_subscription"),
          Some (`Assoc params) ) -> (
          match
            ( List.assoc_opt "subscription" params,
              List.assoc_opt "result" params )
          with
          | Some (`String actual), Some result -> (
              if not (String.equal actual subscription_id) then Ok None
              else
                match kind with
                | New_heads ->
                    Result.map
                      (fun head -> Some (New_head head))
                      (head_of_yojson result)
                | Logs _ ->
                    Result.map
                      (fun log -> Some (Log log))
                      (Types.log_of_yojson result))
          | _ -> Error "subscription params require subscription and result")
      | _ -> Error "invalid eth_subscription notification")
  | _ -> Error "subscription notification must be an object"

module Reconnect = struct
  type state = Disconnected | Connecting | Subscribing | Active of string
  type action = Connect | Send_subscribe of Yojson.Safe.t | Ready | Ignore
  type t = { kind : kind; mutable state : state; mutable generation : int }

  let create kind = { kind; state = Disconnected; generation = 0 }
  let state t = t.state
  let generation t = t.generation

  let start t =
    match t.state with
    | Disconnected ->
        t.state <- Connecting;
        Connect
    | Connecting | Subscribing | Active _ -> Ignore

  let connected ~id t =
    match t.state with
    | Connecting ->
        t.state <- Subscribing;
        Ok (Send_subscribe (Codec.request ~id (subscribe t.kind)))
    | _ -> Error "connected event received outside Connecting state"

  let subscribed t subscription_id =
    match t.state with
    | Subscribing ->
        t.state <- Active subscription_id;
        Ok Ready
    | _ -> Error "subscription response received outside Subscribing state"

  let disconnected t =
    t.generation <- t.generation + 1;
    t.state <- Connecting;
    Connect

  let notification t value =
    match t.state with
    | Active subscription_id ->
        notification_of_yojson ~subscription_id t.kind value
    | Disconnected | Connecting | Subscribing -> Ok None
end
