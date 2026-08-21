val request : id:Id.t -> 'a Method.t -> Yojson.Safe.t
val request_string : id:Id.t -> 'a Method.t -> string
val decode_response : id:Id.t -> 'a Method.t -> string -> ('a, Error.t) result

val decode_response_json :
  id:Id.t -> 'a Method.t -> Yojson.Safe.t -> ('a, Error.t) result
