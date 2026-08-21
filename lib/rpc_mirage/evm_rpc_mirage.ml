module Make (R : Resolver_mirage.S) (S : Conduit_mirage.S) = struct
  module Cohttp_client = Cohttp_mirage.Client.Make (R) (S)
  module Base = Evm_rpc_cohttp.Make (Cohttp_client)
  include Base

  let create ?authenticator ?headers ?max_response_bytes ~resolver ~conduit uri
      =
    let ctx = Cohttp_client.ctx ?authenticator resolver conduit in
    Base.create ~ctx ?headers ?max_response_bytes uri
end
