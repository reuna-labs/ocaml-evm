type response = Return of Yojson.Safe.t | Raise of Error.t

type expectation = {
  method_ : string;
  params : Yojson.Safe.t list;
  response : response;
}

type t

val create : expectation list -> t

val request :
  t ->
  method_:string ->
  params:Yojson.Safe.t list ->
  (Yojson.Safe.t, Error.t) result

val remaining : t -> int
val calls : t -> (string * Yojson.Safe.t list) list

module Provider : Provider.S with type t = t and type 'a io = 'a
