let request ~id method_ =
  `Assoc
    [
      ("jsonrpc", `String "2.0");
      ("id", Id.to_yojson id);
      ("method", `String (Method.name method_));
      ("params", `List (Method.params method_));
    ]

let request_string ~id method_ = Yojson.Safe.to_string (request ~id method_)

let decode_response_json ~id method_ = function
  | `Assoc fields -> (
      match List.assoc_opt "jsonrpc" fields with
      | Some (`String "2.0") -> (
          let actual_id =
            match List.assoc_opt "id" fields with
            | Some `Null | None -> None
            | Some value -> Result.to_option (Id.of_yojson value)
          in
          if
            not
              (match actual_id with
              | Some actual -> Id.equal id actual
              | None -> false)
          then Error (Error.Id_mismatch { expected = id; actual = actual_id })
          else
            match
              (List.assoc_opt "result" fields, List.assoc_opt "error" fields)
            with
            | Some value, None -> (
                match Method.decode method_ value with
                | Ok result -> Ok result
                | Error message ->
                    Error
                      (Error.Decode
                         { method_ = Method.name method_; message; value }))
            | None, Some value -> (
                match Error.rpc_of_yojson value with
                | Ok error -> Error (Error.Rpc error)
                | Error message -> Error (Error.Invalid_response message))
            | Some _, Some _ ->
                Error
                  (Error.Invalid_response
                     "response contains both result and error")
            | None, None ->
                Error
                  (Error.Invalid_response
                     "response contains neither result nor error"))
      | _ -> Error (Error.Invalid_response "missing jsonrpc=2.0 marker"))
  | _ -> Error (Error.Invalid_response "response must be a JSON object")

let decode_response ~id method_ body =
  try decode_response_json ~id method_ (Yojson.Safe.from_string body)
  with Yojson.Json_error message -> Error (Error.Malformed_json message)
