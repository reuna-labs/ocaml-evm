module type S = sig
  type t
  type 'a io

  val return : 'a -> 'a io
  val bind : 'a io -> ('a -> 'b io) -> 'b io

  val request :
    t ->
    method_:string ->
    params:Yojson.Safe.t list ->
    (Yojson.Safe.t, Error.t) result io
end

module Make (P : S) = struct
  let call provider method_ =
    P.bind
      (P.request
         provider
         ~method_:(Method.name method_)
         ~params:(Method.params method_))
      (function
        | Error _ as error -> P.return error
        | Ok value -> (
            match Method.decode method_ value with
            | Ok value -> P.return (Ok value)
            | Error message ->
                P.return
                  (Error
                     (Error.Decode
                        { method_ = Method.name method_; message; value }))))
end

module type HTTP = sig
  type t
  type 'a io

  val return : 'a -> 'a io
  val bind : 'a io -> ('a -> 'b io) -> 'b io
  val post : t -> body:string -> (string, string) result io
end

module Of_http (H : HTTP) = struct
  type t = H.t
  type 'a io = 'a H.io

  let return = H.return
  let bind = H.bind

  let request transport ~method_ ~params =
    let id = Id.Int 0 in
    let raw_method = Method.make ~name:method_ ~params Result.ok in
    H.bind
      (H.post transport ~body:(Codec.request_string ~id raw_method))
      (function
        | Error message -> H.return (Error (Error.Transport message))
        | Ok body -> H.return (Codec.decode_response ~id raw_method body))
end
