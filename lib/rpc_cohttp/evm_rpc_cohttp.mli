module Make (C : Cohttp_lwt.S.Client) : sig
  type t

  val create :
    ?ctx:C.ctx ->
    ?headers:Http.Header.t ->
    ?max_response_bytes:int ->
    Uri.t ->
    t

  val uri : t -> Uri.t

  module Provider : Evm_rpc.Provider.S with type t = t and type 'a io = 'a Lwt.t

  module Client : sig
    val call : t -> 'a Evm_rpc.Method.t -> ('a, Evm_rpc.Error.t) result Lwt.t
  end
end
