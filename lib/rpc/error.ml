type rpc = { code : int; message : string; data : Yojson.Safe.t option }

type t =
  | Transport of string
  | Malformed_json of string
  | Invalid_response of string
  | Id_mismatch of { expected : Id.t; actual : Id.t option }
  | Rpc of rpc
  | Decode of { method_ : string; message : string; value : Yojson.Safe.t }

let pp_rpc ppf e = Format.fprintf ppf "JSON-RPC error %d: %s" e.code e.message

let pp ppf = function
  | Transport message -> Format.fprintf ppf "transport error: %s" message
  | Malformed_json message -> Format.fprintf ppf "malformed JSON: %s" message
  | Invalid_response message ->
      Format.fprintf ppf "invalid JSON-RPC response: %s" message
  | Id_mismatch { expected; actual } ->
      Format.fprintf
        ppf
        "JSON-RPC response ID mismatch (expected %a, got %a)"
        Id.pp
        expected
        (Format.pp_print_option Id.pp)
        actual
  | Rpc e -> pp_rpc ppf e
  | Decode { method_; message; _ } ->
      Format.fprintf ppf "cannot decode %s result: %s" method_ message

let rpc_of_yojson = function
  | `Assoc fields -> (
      match (List.assoc_opt "code" fields, List.assoc_opt "message" fields) with
      | Some (`Int code), Some (`String message) ->
          Ok { code; message; data = List.assoc_opt "data" fields }
      | Some (`Intlit code), Some (`String message) -> (
          match int_of_string_opt code with
          | Some code ->
              Ok { code; message; data = List.assoc_opt "data" fields }
          | None -> Error "JSON-RPC error code is out of range")
      | _ -> Error "JSON-RPC error requires integer code and string message")
  | _ -> Error "JSON-RPC error must be an object"
