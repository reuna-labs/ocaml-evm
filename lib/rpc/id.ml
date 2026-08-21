type t = Int of int | String of string

let equal a b =
  match (a, b) with
  | Int a, Int b -> Int.equal a b
  | String a, String b -> String.equal a b
  | _ -> false

let to_yojson = function
  | Int n -> `Int n
  | String s -> `String s

let of_yojson = function
  | `Int n -> Ok (Int n)
  | `Intlit s -> (
      match int_of_string_opt s with
      | Some n -> Ok (Int n)
      | None -> Error "JSON-RPC numeric ID does not fit an OCaml int")
  | `String s -> Ok (String s)
  | _ -> Error "JSON-RPC ID must be an integer or string"

let pp ppf = function
  | Int n -> Format.pp_print_int ppf n
  | String s -> Format.fprintf ppf "%S" s
