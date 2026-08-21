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

module Make (T : TRANSPORT) : sig
  type t

  type event =
    | Notification of Evm_rpc.Subscription.notification
    | Ignored
    | Reconnect_required of string

  val create : ?max_message_bytes:int -> T.t -> Evm_rpc.Subscription.kind -> t
  val connect : t -> (unit, string) result T.io
  val next : t -> event T.io
  val disconnect : t -> unit T.io
  val generation : t -> int
end
