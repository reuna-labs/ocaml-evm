type t =
  | Error_string of string
  | Panic of Z.t
  | Custom of { selector : string; data : string }
  | Malformed of string

let error_selector = Evm_abi.selector "Error(string)"
let panic_selector = Evm_abi.selector "Panic(uint256)"

let of_data raw =
  if String.length raw < 4 then None
  else
    let selector = String.sub raw 0 4 in
    let body = String.sub raw 4 (String.length raw - 4) in
    if String.equal selector error_selector then
      match Evm_abi.decode [ Evm_abi.TString ] body with
      | Ok [ Evm_abi.String message ] -> Some (Error_string message)
      | Ok _ | Error _ -> Some (Malformed raw)
    else if String.equal selector panic_selector then
      match Evm_abi.decode [ Evm_abi.TUint 256 ] body with
      | Ok [ Evm_abi.Uint code ] -> Some (Panic code)
      | Ok _ | Error _ -> Some (Malformed raw)
    else Some (Custom { selector; data = body })

let rec find_data = function
  | `String value when String.length value >= 2 && String.sub value 0 2 = "0x"
    -> Result.to_option (Evm_types.Hex.decode value)
  | `Assoc fields ->
      List.find_map
        (fun name ->
          match List.assoc_opt name fields with
          | None -> None
          | Some value -> find_data value)
        [ "data"; "result"; "return"; "originalError" ]
  | _ -> None

let of_rpc_error error =
  match error.Error.data with
  | None -> None
  | Some value -> Option.bind (find_data value) of_data

let pp ppf = function
  | Error_string message -> Format.fprintf ppf "Error(%S)" message
  | Panic code -> Format.fprintf ppf "Panic(0x%s)" (Z.format "%x" code)
  | Custom { selector; _ } ->
      Format.fprintf ppf "custom error 0x%s" (Evm_types.Hex.encode_raw selector)
  | Malformed _ -> Format.pp_print_string ppf "malformed revert data"
