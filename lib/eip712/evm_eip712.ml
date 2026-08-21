type member = { name : string; typ : string }
type schema = (string * member list) list

type t = {
  types : schema;
  primary_type : string;
  domain : Yojson.Safe.t;
  message : Yojson.Safe.t;
}

type limits = {
  max_input_bytes : int;
  max_json_depth : int;
  max_json_nodes : int;
  max_array_length : int;
  max_object_fields : int;
  max_string_bytes : int;
  max_types : int;
  max_members_per_type : int;
  max_identifier_bytes : int;
}

let default_limits =
  {
    max_input_bytes = 4 * 1024 * 1024;
    max_json_depth = 64;
    max_json_nodes = 100_000;
    max_array_length = 4_096;
    max_object_fields = 4_096;
    max_string_bytes = 1024 * 1024;
    max_types = 256;
    max_members_per_type = 256;
    max_identifier_bytes = 256;
  }

let ( >>= ) = Result.bind

let validate_limits limits =
  if limits.max_input_bytes <= 0 then
    Error "EIP-712 max_input_bytes must be positive"
  else if limits.max_json_depth < 0 then
    Error "EIP-712 max_json_depth must be non-negative"
  else if limits.max_json_nodes <= 0 then
    Error "EIP-712 max_json_nodes must be positive"
  else if limits.max_array_length < 0 then
    Error "EIP-712 max_array_length must be non-negative"
  else if limits.max_object_fields < 0 then
    Error "EIP-712 max_object_fields must be non-negative"
  else if limits.max_string_bytes < 0 then
    Error "EIP-712 max_string_bytes must be non-negative"
  else if limits.max_types < 0 then
    Error "EIP-712 max_types must be non-negative"
  else if limits.max_members_per_type < 0 then
    Error "EIP-712 max_members_per_type must be non-negative"
  else if limits.max_identifier_bytes < 0 then
    Error "EIP-712 max_identifier_bytes must be non-negative"
  else Ok ()

let validate_json limits json =
  let nodes = ref 0 in
  let bump () =
    incr nodes;
    if !nodes > limits.max_json_nodes then
      Error "EIP-712 JSON node limit exceeded"
    else Ok ()
  in
  let check_string value =
    if String.length value > limits.max_string_bytes then
      Error "EIP-712 JSON string limit exceeded"
    else Ok ()
  in
  let rec walk depth json =
    if depth > limits.max_json_depth then
      Error "EIP-712 JSON nesting limit exceeded"
    else
      bump () >>= fun () ->
      match json with
      | `Assoc fields ->
          if List.length fields > limits.max_object_fields then
            Error "EIP-712 JSON object field limit exceeded"
          else
            List.fold_left
              (fun acc (name, value) ->
                acc >>= fun () ->
                check_string name >>= fun () -> walk (depth + 1) value)
              (Ok ())
              fields
      | `List values | `Tuple values ->
          if List.length values > limits.max_array_length then
            Error "EIP-712 JSON array length limit exceeded"
          else
            List.fold_left
              (fun acc value -> acc >>= fun () -> walk (depth + 1) value)
              (Ok ())
              values
      | `Variant (name, value) -> (
          check_string name >>= fun () ->
          match value with
          | None -> Ok ()
          | Some value -> walk (depth + 1) value)
      | `String value | `Intlit value -> check_string value
      | `Null | `Bool _ | `Int _ | `Float _ -> Ok ()
  in
  validate_limits limits >>= fun () -> walk 0 json

let check_identifier limits what value =
  if String.length value > limits.max_identifier_bytes then
    Error (what ^ " exceeds identifier limit")
  else Ok value

let hash s =
  Digestif.KECCAK_256.digest_string s |> Digestif.KECCAK_256.to_raw_string

let hash_value s = Result.get_ok (Evm_types.Hash.of_bytes (hash s))

let assoc = function
  | `Assoc xs -> Ok xs
  | _ -> Error "expected a JSON object"

let required_string name fields =
  match List.assoc_opt name fields with
  | Some (`String s) -> Ok s
  | Some _ -> Error (name ^ " must be a string")
  | None -> Error (name ^ " is required")

let member_of_json limits json =
  assoc json >>= fun fields ->
  required_string "name" fields >>= fun name ->
  check_identifier limits "EIP-712 member name" name >>= fun name ->
  required_string "type" fields >>= fun typ ->
  check_identifier limits "EIP-712 member type" typ >>= fun typ ->
  Ok { name; typ }

let schema_of_json limits = function
  | `Assoc defs ->
      if List.length defs > limits.max_types then
        Error "EIP-712 type count limit exceeded"
      else
        List.fold_left
          (fun acc (name, json) ->
            acc >>= fun types ->
            check_identifier limits "EIP-712 type name" name >>= fun name ->
            match json with
            | `List members ->
                if List.length members > limits.max_members_per_type then
                  Error ("member count limit exceeded for " ^ name)
                else
                  List.fold_left
                    (fun acc m ->
                      acc >>= fun ms ->
                      member_of_json limits m >>= fun m -> Ok (m :: ms))
                    (Ok [])
                    members
                  >>= fun members -> Ok ((name, List.rev members) :: types)
            | _ -> Error ("type " ^ name ^ " must be an array"))
          (Ok [])
          defs
        |> Result.map List.rev
  | _ -> Error "types must be an object"

let of_yojson_with_limits limits json =
  validate_json limits json >>= fun () ->
  assoc json >>= fun fields ->
  (match List.assoc_opt "types" fields with
  | Some x -> schema_of_json limits x
  | None -> Error "types is required")
  >>= fun types ->
  required_string "primaryType" fields >>= fun primary_type ->
  check_identifier limits "EIP-712 primary type" primary_type
  >>= fun primary_type ->
  (match List.assoc_opt "domain" fields with
  | Some (`Assoc _ as x) -> Ok x
  | _ -> Error "domain must be an object")
  >>= fun domain ->
  (match List.assoc_opt "message" fields with
  | Some (`Assoc _ as x) -> Ok x
  | _ -> Error "message must be an object")
  >>= fun message -> Ok { types; primary_type; domain; message }

let of_yojson json = of_yojson_with_limits default_limits json

let of_json_string_with_limits limits json =
  validate_limits limits >>= fun () ->
  if String.length json > limits.max_input_bytes then
    Error
      (Printf.sprintf
         "EIP-712 JSON exceeds input byte limit (%d > %d)"
         (String.length json)
         limits.max_input_bytes)
  else
    try of_yojson_with_limits limits (Yojson.Safe.from_string json)
    with Yojson.Json_error message ->
      Error ("invalid EIP-712 JSON: " ^ message)

let of_json_string json = of_json_string_with_limits default_limits json

let definition schema name =
  match List.assoc_opt name schema with
  | Some x -> Ok x
  | None -> Error ("unknown EIP-712 type " ^ name)

let base_type typ =
  match String.index_opt typ '[' with
  | Some i -> String.sub typ 0 i
  | None -> typ

let is_atomic typ =
  match Evm_abi.ty_of_string typ with
  | Ok _ -> true
  | Error _ -> false

let dependencies schema root =
  let rec visit seen name =
    if List.mem name seen then Ok seen
    else
      definition schema name >>= fun members ->
      List.fold_left
        (fun acc member ->
          acc >>= fun seen ->
          let dep = base_type member.typ in
          if is_atomic dep then Ok seen else visit seen dep)
        (Ok (name :: seen))
        members
  in
  visit [] root
  |> Result.map (fun names ->
         names
         |> List.filter (fun n -> n <> root)
         |> List.sort_uniq String.compare)

let render_definition schema name =
  definition schema name
  |> Result.map (fun members ->
         name ^ "("
         ^ String.concat "," (List.map (fun m -> m.typ ^ " " ^ m.name) members)
         ^ ")")

let encode_type_unchecked schema name =
  dependencies schema name >>= fun deps ->
  render_definition schema name >>= fun root ->
  List.fold_left
    (fun acc dep ->
      acc >>= fun out ->
      render_definition schema dep |> Result.map (fun d -> out ^ d))
    (Ok root)
    deps

let type_hash_unchecked schema name =
  encode_type_unchecked schema name |> Result.map hash_value

let z_of_json = function
  | `Int n -> Ok (Z.of_int n)
  | `Intlit s | `String s -> (
      try
        if String.length s > 2 && String.sub s 0 2 = "0x" then
          Ok (Z.of_string_base 16 (String.sub s 2 (String.length s - 2)))
        else Ok (Z.of_string s)
      with Invalid_argument _ -> Error ("invalid integer " ^ s))
  | _ -> Error "integer value must be an integer or string"

let word_of_z z =
  match Evm_types.be_of_z ~len:32 z with
  | Ok x -> Ok x
  | Error _ -> Error "integer does not fit 256 bits"

let signed_word bits z =
  let min = Z.neg (Z.shift_left Z.one (bits - 1))
  and max = Z.shift_left Z.one (bits - 1) in
  if Z.lt z min || Z.geq z max then
    Error (Printf.sprintf "int%d out of range" bits)
  else word_of_z (if Z.sign z < 0 then Z.add (Z.shift_left Z.one 256) z else z)

let unsigned_word bits z =
  if Z.sign z < 0 || Z.numbits z > bits then
    Error (Printf.sprintf "uint%d out of range" bits)
  else word_of_z z

let decode_hex_json = function
  | `String s ->
      Evm_types.Hex.decode s
      |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)
  | _ -> Error "byte value must be a 0x-prefixed string"

let split_array typ =
  let len = String.length typ in
  if len > 1 && typ.[len - 1] = ']' then
    match String.rindex_opt typ '[' with
    | Some i -> Some (String.sub typ 0 i, String.sub typ (i + 1) (len - i - 2))
    | None -> None
  else None

let rec encode_value schema typ json =
  match split_array typ with
  | Some (inner, size) -> (
      match json with
      | `List values -> (
          match
            if size = "" then Some (List.length values)
            else int_of_string_opt size
          with
          | Some n when n = List.length values ->
              List.fold_left
                (fun acc value ->
                  acc >>= fun out ->
                  encode_value schema inner value
                  |> Result.map (fun word -> out ^ word))
                (Ok "")
                values
              |> Result.map hash
          | _ -> Error ("array length mismatch for " ^ typ))
      | _ -> Error (typ ^ " requires a JSON array"))
  | None -> (
      match Evm_abi.ty_of_string typ with
      | Error _ -> hash_struct_raw schema typ json
      | Ok abi_ty -> (
          match (abi_ty, json) with
          | Evm_abi.TAddress, `String s ->
              Evm_types.Address.of_hex s
              |> Result.map_error (Format.asprintf "%a" Evm_types.pp_error)
              >>= fun a ->
              Ok (String.make 12 '\000' ^ Evm_types.Address.to_bytes a)
          | Evm_abi.TBool, `Bool b -> word_of_z (if b then Z.one else Z.zero)
          | Evm_abi.TUint bits, v -> z_of_json v >>= unsigned_word bits
          | Evm_abi.TInt bits, v -> z_of_json v >>= signed_word bits
          | Evm_abi.TFixedBytes n, v ->
              decode_hex_json v >>= fun bytes ->
              if String.length bytes <> n then
                Error (Printf.sprintf "bytes%d has wrong length" n)
              else Ok (bytes ^ String.make (32 - n) '\000')
          | Evm_abi.TBytes, v -> decode_hex_json v |> Result.map hash
          | Evm_abi.TString, `String s -> Ok (hash s)
          | _ -> Error ("invalid value for " ^ typ)))

and hash_struct_raw schema name json =
  definition schema name >>= fun members ->
  assoc json >>= fun fields ->
  type_hash_unchecked schema name >>= fun type_hash ->
  List.fold_left
    (fun acc member ->
      acc >>= fun encoded ->
      match List.assoc_opt member.name fields with
      | None -> Error ("missing field " ^ member.name ^ " in " ^ name)
      | Some value ->
          encode_value schema member.typ value
          |> Result.map (fun word -> encoded ^ word))
    (Ok (Evm_types.Hash.to_bytes type_hash))
    members
  |> Result.map hash

and hash_struct_unchecked schema name json =
  hash_struct_raw schema name json
  |> Result.map (fun raw -> Result.get_ok (Evm_types.Hash.of_bytes raw))

let validate_schema limits schema =
  validate_limits limits >>= fun () ->
  if List.length schema > limits.max_types then
    Error "EIP-712 type count limit exceeded"
  else
    List.fold_left
      (fun acc (name, members) ->
        acc >>= fun () ->
        check_identifier limits "EIP-712 type name" name >>= fun _ ->
        if List.length members > limits.max_members_per_type then
          Error ("member count limit exceeded for " ^ name)
        else
          List.fold_left
            (fun acc member ->
              acc >>= fun () ->
              check_identifier limits "EIP-712 member name" member.name
              >>= fun _ ->
              check_identifier limits "EIP-712 member type" member.typ
              |> Result.map (fun _ -> ()))
            (Ok ())
            members)
      (Ok ())
      schema

let encode_type_with_limits limits schema name =
  validate_schema limits schema >>= fun () ->
  check_identifier limits "EIP-712 root type" name >>= fun name ->
  encode_type_unchecked schema name

let encode_type schema name = encode_type_with_limits default_limits schema name

let type_hash_with_limits limits schema name =
  encode_type_with_limits limits schema name |> Result.map hash_value

let type_hash schema name = type_hash_with_limits default_limits schema name

let hash_struct_with_limits limits schema name json =
  validate_schema limits schema >>= fun () ->
  check_identifier limits "EIP-712 root type" name >>= fun name ->
  validate_json limits json >>= fun () -> hash_struct_unchecked schema name json

let hash_struct schema name json =
  hash_struct_with_limits default_limits schema name json

let domain_separator_with_limits limits t =
  validate_schema limits t.types >>= fun () ->
  validate_json limits t.domain >>= fun () ->
  hash_struct_unchecked t.types "EIP712Domain" t.domain

let domain_separator t = domain_separator_with_limits default_limits t

let digest_with_limits limits t =
  validate_schema limits t.types >>= fun () ->
  check_identifier limits "EIP-712 primary type" t.primary_type
  >>= fun primary_type ->
  validate_json limits t.domain >>= fun () ->
  validate_json limits t.message >>= fun () ->
  hash_struct_unchecked t.types "EIP712Domain" t.domain >>= fun domain ->
  hash_struct_unchecked t.types primary_type t.message >>= fun message ->
  Ok
    (hash_value
       ("\x19\x01"
       ^ Evm_types.Hash.to_bytes domain
       ^ Evm_types.Hash.to_bytes message))

let digest t = digest_with_limits default_limits t
