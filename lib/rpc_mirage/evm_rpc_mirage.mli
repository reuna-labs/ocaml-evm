module Make (R : Resolver_mirage.S) (S : Conduit_mirage.S) : sig
  module Cohttp_client : Cohttp_lwt.S.Client

  type t

  val create :
    ?authenticator:X509.Authenticator.t ->
    ?headers:Http.Header.t ->
    ?max_response_bytes:int ->
    resolver:R.t ->
    conduit:S.t ->
    Uri.t ->
    t

  val uri : t -> Uri.t

  module Provider : Evm_rpc.Provider.S with type t = t and type 'a io = 'a Lwt.t

  module Client : sig
    val call : t -> 'a Evm_rpc.Method.t -> ('a, Evm_rpc.Error.t) result Lwt.t
  end
end
