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

module Head_tracker : sig
  type t

  val create : ?capacity:int -> unit -> t
  val observe : t -> head -> head_update
  val tip : t -> head option
  val history : t -> head list
  val reset : t -> head list -> (unit, string) result
end

type kind = New_heads | Logs of Types.log_filter
type notification = New_head of head | Log of Types.log

val subscribe : kind -> string Method.t
val unsubscribe : string -> bool Method.t

val notification_of_yojson :
  subscription_id:string ->
  kind ->
  Yojson.Safe.t ->
  (notification option, string) result

module Reconnect : sig
  type state = Disconnected | Connecting | Subscribing | Active of string
  type action = Connect | Send_subscribe of Yojson.Safe.t | Ready | Ignore
  type t

  val create : kind -> t
  val state : t -> state
  val generation : t -> int
  val start : t -> action
  val connected : id:Id.t -> t -> (action, string) result
  val subscribed : t -> string -> (action, string) result
  val disconnected : t -> action
  val notification : t -> Yojson.Safe.t -> (notification option, string) result
end
