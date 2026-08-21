type t =
  | Error_string of string
  | Panic of Z.t
  | Custom of { selector : string; data : string }
  | Malformed of string

val of_data : string -> t option
val of_rpc_error : Error.rpc -> t option
val pp : Format.formatter -> t -> unit
