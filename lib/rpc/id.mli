type t = Int of int | String of string

val equal : t -> t -> bool
val to_yojson : t -> Yojson.Safe.t
val of_yojson : Yojson.Safe.t -> (t, string) result
val pp : Format.formatter -> t -> unit
