type rpc = { code : int; message : string; data : Yojson.Safe.t option }

type t =
  | Transport of string
  | Malformed_json of string
  | Invalid_response of string
  | Id_mismatch of { expected : Id.t; actual : Id.t option }
  | Rpc of rpc
  | Decode of { method_ : string; message : string; value : Yojson.Safe.t }

val pp_rpc : Format.formatter -> rpc -> unit
val pp : Format.formatter -> t -> unit
val rpc_of_yojson : Yojson.Safe.t -> (rpc, string) result
