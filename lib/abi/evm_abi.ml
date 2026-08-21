(* The core codec originated in ocaml-web3-codec and is maintained here as
   the ownership boundary for EVM-specific formats. *)
(* Ethereum Contract ABI encoding, the head/tail scheme used for
   function call data and event/return values.
   https://docs.soliditylang.org/en/latest/abi-spec.html

   Function selectors use keccak256 (Ethereum's pre-NIST Keccak padding),
   taken here from digestif's [KECCAK_256].

   Both directions validate. Encoding rejects values that do not fit their
   ABI representation (a 20-byte address really must be 20 bytes) rather
   than silently wrapping; decoding rejects malformed and non-canonical
   input, and bounds every length taken from the input against the buffer
   before allocating. *)

type value =
  | Uint of Z.t
  | Int of Z.t
  | Bool of bool
  | Address of string (* 20 bytes *)
  | FixedBytes of string (* bytesN, 1..32 bytes, left-aligned *)
  | Bytes of string (* dynamic *)
  | String of string
  | Array of value list (* T[] *)
  | FixedArray of value list (* T[k] *)
  | Tuple of value list

type ty =
  | TUint of int
  | TInt of int
  | TBool
  | TAddress
  | TFixedBytes of int
  | TBytes
  | TString
  | TArray of ty
  | TFixedArray of ty * int
  | TTuple of ty list

type limits = {
  max_input_bytes : int;
  max_dynamic_bytes : int;
  max_nesting : int;
  max_elements : int;
  max_contract_items : int;
  max_string_bytes : int;
}

let default_limits =
  {
    max_input_bytes = 16 * 1024 * 1024;
    max_dynamic_bytes = 1024 * 1024;
    max_nesting = 64;
    max_elements = 4_096;
    max_contract_items = 4_096;
    max_string_bytes = 4_096;
  }

let validate_limits limits =
  if limits.max_input_bytes <= 0 then
    Error "abi: max_input_bytes must be positive"
  else if limits.max_dynamic_bytes < 0 then
    Error "abi: max_dynamic_bytes must be non-negative"
  else if limits.max_nesting < 0 then
    Error "abi: max_nesting must be non-negative"
  else if limits.max_elements < 0 then
    Error "abi: max_elements must be non-negative"
  else if limits.max_contract_items < 0 then
    Error "abi: max_contract_items must be non-negative"
  else if limits.max_string_bytes < 0 then
    Error "abi: max_string_bytes must be non-negative"
  else Ok ()

(* ---- shared helpers ---- *)

let z_of_be s =
  String.fold_left
    (fun acc c -> Z.add (Z.mul acc (Z.of_int 256)) (Z.of_int (Char.code c)))
    Z.zero
    s

let two256 = Z.shift_left Z.one 256
let two255 = Z.shift_left Z.one 255

(* 32-byte big-endian, two's complement (so negatives sign-extend). *)
let word_of_z z =
  let m = Z.erem z two256 in
  String.init 32 (fun i ->
      Char.chr
        (Z.to_int (Z.logand (Z.shift_right m (8 * (31 - i))) (Z.of_int 0xff))))

let pad_right32 s =
  let r = String.length s mod 32 in
  if r = 0 then s else s ^ String.make (32 - r) '\000'

(* A uintN/intN width must be a multiple of 8 in 8..256; a bytesN width
   must be in 1..32. Both are part of the ABI grammar, so a [ty] that
   violates them is rejected rather than silently reinterpreted. *)
let valid_int_width n = n > 0 && n <= 256 && n mod 8 = 0
let valid_bytes_width n = n >= 1 && n <= 32

(* ---- encoding ---- *)

exception Eerr of string

let rec is_dynamic = function
  | Bytes _ | String _ | Array _ -> true
  | FixedArray vs | Tuple vs -> List.exists is_dynamic vs
  | _ -> false

(* Reject anything that cannot be represented faithfully. Without these
   checks a 32-byte [Address] silently wraps mod 2^256 into a well-formed
   transaction to the wrong recipient, and an over-long [FixedBytes]
   silently shifts every following head/tail offset. *)
let check = function
  | Uint z ->
      if Z.sign z < 0 then raise (Eerr "abi: negative value in Uint");
      if Z.geq z two256 then raise (Eerr "abi: Uint exceeds 256 bits")
  | Int z ->
      if Z.geq z two255 || Z.lt z (Z.neg two255) then
        raise (Eerr "abi: Int does not fit a signed 256-bit word")
  | Address a ->
      if String.length a <> 20 then
        raise
          (Eerr
             (Printf.sprintf
                "abi: Address must be 20 bytes, got %d"
                (String.length a)))
  | FixedBytes b ->
      if not (valid_bytes_width (String.length b)) then
        raise
          (Eerr
             (Printf.sprintf
                "abi: FixedBytes must be 1..32 bytes, got %d"
                (String.length b)))
  | _ -> ()

let rec enc v =
  check v;
  match v with
  | Uint z | Int z -> word_of_z z
  | Bool b -> word_of_z (if b then Z.one else Z.zero)
  | Address a -> word_of_z (z_of_be a)
  | FixedBytes b -> pad_right32 b
  | Bytes b | String b -> word_of_z (Z.of_int (String.length b)) ^ pad_right32 b
  | Array vs -> word_of_z (Z.of_int (List.length vs)) ^ enc_seq vs
  | FixedArray vs -> enc_seq vs
  | Tuple vs -> enc_seq vs

and enc_seq vs =
  let parts = List.map (fun v -> (is_dynamic v, enc v)) vs in
  let head_size =
    List.fold_left
      (fun a (d, e) -> a + if d then 32 else String.length e)
      0
      parts
  in
  let headb = Buffer.create 64 and tailb = Buffer.create 64 in
  let off = ref head_size in
  List.iter
    (fun (d, e) ->
      if d then (
        Buffer.add_string headb (word_of_z (Z.of_int !off));
        Buffer.add_string tailb e;
        off := !off + String.length e)
      else Buffer.add_string headb e)
    parts;
  Buffer.contents headb ^ Buffer.contents tailb

let encode values = try Ok (enc_seq values) with Eerr m -> Error m
let keccak s = Digestif.KECCAK_256.(to_raw_string (digest_string s))
let selector signature = String.sub (keccak signature) 0 4

let encode_call ~signature values =
  match encode values with
  | Ok body -> Ok (selector signature ^ body)
  | Error _ as e -> e

(* [encode_exn]/[encode_call_exn] are for call sites with statically known
   well-formed values (test vectors, constants). They raise
   [Invalid_argument] rather than returning a result. *)
let encode_exn values =
  match encode values with
  | Ok s -> s
  | Error m -> invalid_arg m

let encode_call_exn ~signature values =
  match encode_call ~signature values with
  | Ok s -> s
  | Error m -> invalid_arg m

(* ---- decoding ---- *)

let rec is_dyn = function
  | TBytes | TString | TArray _ -> true
  | TFixedArray (t, _) -> is_dyn t
  | TTuple ts -> List.exists is_dyn ts
  | _ -> false

let rec static_size = function
  | TFixedArray (t, k) -> k * static_size t
  | TTuple ts -> List.fold_left (fun a t -> a + static_size t) 0 ts
  | _ -> 32

exception Derr of string

let check_depth limits depth =
  if depth > limits.max_nesting then raise (Derr "abi: nesting limit exceeded")

let check_elements limits count what =
  if count > limits.max_elements then
    raise
      (Derr
         (Printf.sprintf
            "abi: %s exceeds element limit (%d > %d)"
            what
            count
            limits.max_elements))

let rec validate_type limits depth ty =
  check_depth limits depth;
  match ty with
  | (TUint n | TInt n) when not (valid_int_width n) ->
      raise (Derr "abi: invalid integer width")
  | TFixedBytes n when not (valid_bytes_width n) ->
      raise (Derr "abi: invalid bytesN width")
  | TArray t -> validate_type limits (depth + 1) t
  | TFixedArray (t, count) ->
      if count < 0 then raise (Derr "abi: negative fixed-array length");
      check_elements limits count "fixed-array length";
      validate_type limits (depth + 1) t
  | TTuple tys ->
      check_elements limits (List.length tys) "tuple arity";
      List.iter (validate_type limits (depth + 1)) tys
  | _ -> ()

let add_layout limits left right =
  if left > limits.max_input_bytes - right then
    raise (Derr "abi: static layout exceeds input byte limit")
  else left + right

let multiply_layout limits count size =
  if count <> 0 && size > limits.max_input_bytes / count then
    raise (Derr "abi: static layout exceeds input byte limit")
  else count * size

let rec validate_layout limits = function
  | TFixedArray (ty, count) ->
      multiply_layout limits count (validate_layout limits ty)
  | TTuple tys ->
      List.fold_left
        (fun total ty -> add_layout limits total (validate_layout limits ty))
        0
        tys
  | _ -> 32

let validate_types limits tys =
  check_elements limits (List.length tys) "top-level arity";
  List.iter
    (fun ty ->
      validate_type limits 0 ty;
      ignore (validate_layout limits ty))
    tys

let word_z data pos =
  if pos < 0 || pos + 32 > String.length data then
    raise (Derr "abi: truncated word");
  z_of_be (String.sub data pos 32)

(* Any offset or length read from the input must address a position inside
   the buffer. Rejecting here (rather than at [Z.to_int]) is what stops a
   32-byte length word from either raising [Z.Overflow] out of a function
   whose type says [result], or driving a multi-gigabyte allocation from a
   64-byte input. *)
let word_index data pos ~what =
  let z = word_z data pos in
  if Z.gt z (Z.of_int (String.length data)) then
    raise
      (Derr
         (Printf.sprintf
            "abi: %s exceeds the input (%s > %d)"
            what
            (Z.to_string z)
            (String.length data)));
  Z.to_int z

(* An element of a sequence occupies at least 32 bytes: a static element is
   at least one word, a dynamic one at least its head offset word. So a
   claimed count above (remaining / 32) cannot be honest, and we can reject
   it before building a list of that many elements. *)
let check_count limits data ~after ~count ~what =
  check_elements limits count what;
  let remaining = String.length data - after in
  if count < 0 || remaining < 0 || count > remaining / 32 then
    raise
      (Derr
         (Printf.sprintf
            "abi: %s of %d does not fit the remaining %d bytes"
            what
            count
            (max 0 remaining)))

let rec decode_tuple limits depth tys data base =
  check_depth limits depth;
  check_elements limits (List.length tys) "tuple arity";
  let head = ref 0 in
  List.map
    (fun ty ->
      if is_dyn ty then (
        let off = word_index data (base + !head) ~what:"offset" in
        head := !head + 32;
        (* Offsets are relative to [base] and non-negative, so each jump
           lands strictly after the position it was read from; a chain of
           them therefore terminates. No cycle detection is required. *)
        decode_dynamic limits depth ty data (base + off))
      else
        let v = decode_static limits depth ty data (base + !head) in
        head := !head + static_size ty;
        v)
    tys

and decode_static limits depth ty data pos =
  check_depth limits depth;
  match ty with
  | TUint n ->
      if not (valid_int_width n) then raise (Derr "abi: invalid uintN width");
      let z = word_z data pos in
      if n < 256 && Z.geq z (Z.shift_left Z.one n) then
        raise (Derr (Printf.sprintf "abi: value out of range for uint%d" n));
      Uint z
  | TInt n ->
      if not (valid_int_width n) then raise (Derr "abi: invalid intN width");
      let z = word_z data pos in
      let modn = Z.shift_left Z.one n and half = Z.shift_left Z.one (n - 1) in
      let low = Z.erem z modn in
      let signed = if Z.geq low half then Z.sub low modn else low in
      (* the word must be the sign-extension of the intN value *)
      if not (Z.equal (Z.erem signed two256) z) then
        raise (Derr (Printf.sprintf "abi: value out of range for int%d" n));
      Int signed
  | TBool ->
      let z = word_z data pos in
      if Z.equal z Z.zero then Bool false
      else if Z.equal z Z.one then Bool true
      else raise (Derr "abi: bool must encode as 0 or 1")
  | TAddress ->
      let z = word_z data pos in
      (* the top 12 bytes of an address word are required to be zero *)
      if Z.geq z (Z.shift_left Z.one 160) then
        raise (Derr "abi: address has non-zero high-order bytes");
      Address (String.sub data (pos + 12) 20)
  | TFixedBytes n ->
      if not (valid_bytes_width n) then raise (Derr "abi: invalid bytesN width");
      if pos + 32 > String.length data then raise (Derr "abi: truncated bytesN");
      (* bytesN is left-aligned; the remaining padding must be zero *)
      for i = pos + n to pos + 31 do
        if data.[i] <> '\000' then
          raise (Derr "abi: bytesN has non-zero padding")
      done;
      FixedBytes (String.sub data pos n)
  | TFixedArray (t, k) ->
      if k < 0 then raise (Derr "abi: negative fixed-array length");
      check_count limits data ~after:pos ~count:k ~what:"fixed-array length";
      FixedArray
        (List.init k (fun i ->
             decode_static limits (depth + 1) t data (pos + (i * static_size t))))
  | TTuple ts -> Tuple (decode_tuple limits (depth + 1) ts data pos)
  | TBytes | TString | TArray _ ->
      raise (Derr "abi: dynamic type decoded as static")

and decode_dynamic limits depth ty data pos =
  check_depth limits depth;
  match ty with
  | TBytes | TString ->
      let len = word_index data pos ~what:"length" in
      if len > limits.max_dynamic_bytes then
        raise
          (Derr
             (Printf.sprintf
                "abi: dynamic value exceeds byte limit (%d > %d)"
                len
                limits.max_dynamic_bytes));
      if pos + 32 + len > String.length data then
        raise (Derr "abi: truncated bytes/string");
      let s = String.sub data (pos + 32) len in
      if ty = TString then String s else Bytes s
  | TArray t ->
      let len = word_index data pos ~what:"array length" in
      check_count limits data ~after:(pos + 32) ~count:len ~what:"array length";
      Array
        (decode_tuple
           limits
           (depth + 1)
           (List.init len (fun _ -> t))
           data
           (pos + 32))
  | TFixedArray (t, k) ->
      if k < 0 then raise (Derr "abi: negative fixed-array length");
      check_count limits data ~after:pos ~count:k ~what:"fixed-array length";
      FixedArray
        (decode_tuple limits (depth + 1) (List.init k (fun _ -> t)) data pos)
  | TTuple ts -> Tuple (decode_tuple limits (depth + 1) ts data pos)
  | _ -> raise (Derr "abi: static type decoded as dynamic")

let decode_with_limits limits tys data =
  try
    (match validate_limits limits with
    | Ok () -> ()
    | Error message -> raise (Derr message));
    if String.length data > limits.max_input_bytes then
      raise
        (Derr
           (Printf.sprintf
              "abi: input exceeds byte limit (%d > %d)"
              (String.length data)
              limits.max_input_bytes));
    validate_types limits tys;
    Ok (decode_tuple limits 0 tys data 0)
  with
  | Derr m -> Error m
  | Z.Overflow -> Error "abi: integer field too large"
  | Invalid_argument _ -> Error "abi: index out of bounds"

let decode tys data = decode_with_limits default_limits tys data

(* Strip the 4-byte selector, then decode the parameters. *)
let decode_call_with_limits limits tys data =
  if String.length data < 4 then Error "abi: call data shorter than a selector"
  else
    decode_with_limits limits tys (String.sub data 4 (String.length data - 4))

let decode_call tys data = decode_call_with_limits default_limits tys data

let to_z = function
  | Uint z | Int z -> Some z
  | Bool b -> Some (if b then Z.one else Z.zero)
  | _ -> None

let ( >>= ) = Result.bind

let rec canonical_type = function
  | TUint n -> Printf.sprintf "uint%d" n
  | TInt n -> Printf.sprintf "int%d" n
  | TBool -> "bool"
  | TAddress -> "address"
  | TFixedBytes n -> Printf.sprintf "bytes%d" n
  | TBytes -> "bytes"
  | TString -> "string"
  | TArray t -> canonical_type t ^ "[]"
  | TFixedArray (t, n) -> Printf.sprintf "%s[%d]" (canonical_type t) n
  | TTuple ts -> "(" ^ String.concat "," (List.map canonical_type ts) ^ ")"

let split_array_suffix s =
  let len = String.length s in
  if len > 1 && s.[len - 1] = ']' then
    match String.rindex_opt s '[' with
    | None -> None
    | Some i -> Some (String.sub s 0 i, String.sub s (i + 1) (len - i - 2))
  else None

let valid_width kind n =
  if n >= 8 && n <= 256 && n mod 8 = 0 then Ok n
  else Error (Printf.sprintf "%s width must be a multiple of 8 in 8..256" kind)

let split_tuple_members s =
  let rec loop depth start acc i =
    if i = String.length s then
      if depth <> 0 then Error "unbalanced tuple type"
      else Ok (List.rev (String.sub s start (i - start) :: acc))
    else
      match s.[i] with
      | '(' -> loop (depth + 1) start acc (i + 1)
      | ')' when depth > 0 -> loop (depth - 1) start acc (i + 1)
      | ')' -> Error "unbalanced tuple type"
      | ',' when depth = 0 ->
          loop depth (i + 1) (String.sub s start (i - start) :: acc) (i + 1)
      | _ -> loop depth start acc (i + 1)
  in
  if s = "" then Ok [] else loop 0 0 [] 0

let ty_of_string_with_limits limits s =
  let rec parse depth s =
    if depth > limits.max_nesting then Error "ABI type nesting limit exceeded"
    else if String.length s > limits.max_string_bytes then
      Error "ABI type spelling exceeds string limit"
    else
      match split_array_suffix s with
      | Some (base, "") ->
          Result.map (fun t -> TArray t) (parse (depth + 1) base)
      | Some (base, count) -> (
          match int_of_string_opt count with
          | Some n when n >= 0 && n <= limits.max_elements ->
              Result.map (fun t -> TFixedArray (t, n)) (parse (depth + 1) base)
          | Some n when n > limits.max_elements ->
              Error "ABI fixed-array length exceeds element limit"
          | _ -> Error ("invalid array length in " ^ s))
      | None ->
          if s = "uint" then Ok (TUint 256)
          else if s = "int" then Ok (TInt 256)
          else if s = "bool" then Ok TBool
          else if s = "address" then Ok TAddress
          else if s = "bytes" then Ok TBytes
          else if s = "string" then Ok TString
          else if
            String.length s >= 2 && s.[0] = '(' && s.[String.length s - 1] = ')'
          then
            let body = String.sub s 1 (String.length s - 2) in
            split_tuple_members body >>= fun members ->
            if List.length members > limits.max_elements then
              Error "ABI tuple arity exceeds element limit"
            else
              List.fold_left
                (fun acc member ->
                  acc >>= fun types ->
                  parse (depth + 1) member
                  |> Result.map (fun typ -> typ :: types))
                (Ok [])
                members
              |> Result.map (fun types -> TTuple (List.rev types))
          else if String.length s > 4 && String.sub s 0 4 = "uint" then
            match int_of_string_opt (String.sub s 4 (String.length s - 4)) with
            | Some n -> Result.map (fun n -> TUint n) (valid_width "uint" n)
            | None -> Error ("invalid ABI type " ^ s)
          else if String.length s > 3 && String.sub s 0 3 = "int" then
            match int_of_string_opt (String.sub s 3 (String.length s - 3)) with
            | Some n -> Result.map (fun n -> TInt n) (valid_width "int" n)
            | None -> Error ("invalid ABI type " ^ s)
          else if String.length s > 5 && String.sub s 0 5 = "bytes" then
            match int_of_string_opt (String.sub s 5 (String.length s - 5)) with
            | Some n when n >= 1 && n <= 32 -> Ok (TFixedBytes n)
            | _ -> Error ("bytesN width must be in 1..32: " ^ s)
          else Error ("unsupported ABI type " ^ s)
  in
  validate_limits limits >>= fun () -> parse 0 s

let ty_of_string s = ty_of_string_with_limits default_limits s

type parameter = { name : string; ty : ty; indexed : bool }

type item =
  | Function of {
      name : string;
      inputs : parameter list;
      outputs : parameter list;
      state_mutability : string option;
    }
  | Event of { name : string; inputs : parameter list; anonymous : bool }
  | Error of { name : string; inputs : parameter list }
  | Constructor of { inputs : parameter list; state_mutability : string option }
  | Fallback
  | Receive

let field name fields = List.assoc_opt name fields

let bool_field ?(default = false) name fields =
  match field name fields with
  | Some (`Bool b) -> Ok b
  | None -> Ok default
  | _ -> Error (name ^ " must be a boolean")

let string_field ?default name fields =
  match (field name fields, default) with
  | Some (`String s), _ -> Ok s
  | None, Some d -> Ok d
  | None, None -> Error (name ^ " is required")
  | _ -> Error (name ^ " must be a string")

let bounded_string limits what value =
  if String.length value > limits.max_string_bytes then
    Result.Error (what ^ " exceeds string limit")
  else Result.Ok value

let parameter_of_yojson_with_limits limits json =
  let rec parameter depth json : (parameter, string) result =
    match json with
    | `Assoc fields ->
        if depth > limits.max_nesting then
          Error "ABI parameter nesting limit exceeded"
        else
          let open Result in
          string_field ~default:"" "name" fields >>= fun name ->
          bounded_string limits "ABI parameter name" name >>= fun name ->
          string_field "type" fields >>= fun spelling ->
          bounded_string limits "ABI parameter type" spelling
          >>= fun spelling ->
          bool_field "indexed" fields >>= fun indexed ->
          (if String.length spelling >= 5 && String.sub spelling 0 5 = "tuple"
           then
             match field "components" fields with
             | Some (`List xs) ->
                 if List.length xs > limits.max_elements then
                   Error "ABI tuple component count exceeds element limit"
                 else
                   let rec loop acc = function
                     | [] -> Ok (List.rev acc)
                     | x :: rest ->
                         parameter (depth + 1) x >>= fun p ->
                         loop (p.ty :: acc) rest
                   in
                   loop [] xs >>= fun ts ->
                   let suffix =
                     String.sub spelling 5 (String.length spelling - 5)
                   in
                   let arrays t suffix =
                     if suffix = "" then Ok t
                     else
                       ty_of_string_with_limits
                         limits
                         (canonical_type t ^ suffix)
                   in
                   arrays (TTuple ts) suffix
             | _ -> Error "tuple parameter requires components"
           else ty_of_string_with_limits limits spelling)
          >>= fun ty -> Ok { name; ty; indexed }
    | _ -> Error "ABI parameter must be an object"
  in
  validate_limits limits >>= fun () -> parameter 0 json

let parameters limits name fields =
  match field name fields with
  | None -> Ok []
  | Some (`List xs) ->
      if List.length xs > limits.max_elements then
        Error (name ^ " exceeds parameter limit")
      else
        List.fold_left
          (fun acc x ->
            let open Result in
            acc >>= fun ps ->
            parameter_of_yojson_with_limits limits x >>= fun p -> Ok (p :: ps))
          (Ok [])
          xs
        |> Result.map List.rev
  | _ -> Error (name ^ " must be an array")

let item_of_yojson_with_limits limits json : (item, string) result =
  validate_limits limits >>= fun () ->
  match json with
  | `Assoc fields -> (
      let open Result in
      string_field "type" fields >>= fun kind ->
      bounded_string limits "ABI item type" kind >>= fun kind ->
      parameters limits "inputs" fields >>= fun inputs ->
      let state_mutability =
        match field "stateMutability" fields with
        | Some (`String x) -> Some x
        | _ -> None
      in
      match kind with
      | "function" ->
          string_field "name" fields >>= fun name ->
          bounded_string limits "ABI function name" name >>= fun name ->
          parameters limits "outputs" fields >>= fun outputs ->
          Ok (Function { name; inputs; outputs; state_mutability })
      | "event" ->
          string_field "name" fields >>= fun name ->
          bounded_string limits "ABI event name" name >>= fun name ->
          bool_field "anonymous" fields >>= fun anonymous ->
          Ok (Event { name; inputs; anonymous })
      | "error" ->
          string_field "name" fields >>= fun name ->
          bounded_string limits "ABI error name" name >>= fun name ->
          Ok (Error { name; inputs } : item)
      | "constructor" -> Ok (Constructor { inputs; state_mutability })
      | "fallback" -> Ok Fallback
      | "receive" -> Ok Receive
      | x -> Error ("unsupported ABI item type " ^ x))
  | _ -> Error "ABI item must be an object"

let item_of_yojson json = item_of_yojson_with_limits default_limits json

let contract_of_yojson_with_limits limits json : (item list, string) result =
  validate_limits limits >>= fun () ->
  match json with
  | `List xs ->
      if List.length xs > limits.max_contract_items then
        Error "contract ABI exceeds item limit"
      else
        List.fold_left
          (fun acc x ->
            let open Result in
            acc >>= fun items ->
            item_of_yojson_with_limits limits x >>= fun item ->
            Ok (item :: items))
          (Ok [])
          xs
        |> Result.map List.rev
  | _ -> Error "contract ABI must be an array"

let contract_of_yojson json = contract_of_yojson_with_limits default_limits json

let contract_of_json_string_with_limits limits json =
  validate_limits limits >>= fun () ->
  if String.length json > limits.max_input_bytes then
    Result.Error
      (Printf.sprintf
         "contract ABI JSON exceeds input byte limit (%d > %d)"
         (String.length json)
         limits.max_input_bytes)
  else
    try contract_of_yojson_with_limits limits (Yojson.Safe.from_string json)
    with Yojson.Json_error message ->
      Result.Error ("invalid ABI JSON: " ^ message)

let contract_of_json_string json =
  contract_of_json_string_with_limits default_limits json

let function_signature name inputs =
  name ^ "("
  ^ String.concat "," (List.map (fun p -> canonical_type p.ty) inputs)
  ^ ")"
