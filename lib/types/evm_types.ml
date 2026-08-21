type error =
  [ `Invalid_hex of string
  | `Invalid_length of int * int
  | `Invalid_range of string
  | `Non_canonical of string
  | `Checksum_mismatch ]

let pp_error ppf = function
  | `Invalid_hex s -> Format.fprintf ppf "invalid hexadecimal: %s" s
  | `Invalid_length (expected, actual) ->
      Format.fprintf
        ppf
        "invalid length: expected %d bytes, got %d"
        expected
        actual
  | `Invalid_range s -> Format.fprintf ppf "invalid range: %s" s
  | `Non_canonical s -> Format.fprintf ppf "non-canonical encoding: %s" s
  | `Checksum_mismatch -> Format.pp_print_string ppf "EIP-55 checksum mismatch"

let z_of_be s =
  String.fold_left
    (fun acc c -> Z.logor (Z.shift_left acc 8) (Z.of_int (Char.code c)))
    Z.zero
    s

let be_of_z ~len z =
  if Z.sign z < 0 || Z.numbits z > len * 8 then
    Error (`Invalid_range (Printf.sprintf "value does not fit %d bytes" len))
  else
    Ok
      (String.init len (fun i ->
           Char.chr (Z.to_int (Z.extract z (8 * (len - i - 1)) 8))))

module Hex = struct
  let digit n = if n < 10 then Char.chr (48 + n) else Char.chr (87 + n)

  let encode_raw s =
    String.init
      (String.length s * 2)
      (fun i ->
        let byte = Char.code s.[i / 2] in
        digit (if i mod 2 = 0 then byte lsr 4 else byte land 0x0f))

  let encode s = "0x" ^ encode_raw s

  let nibble = function
    | '0' .. '9' as c -> Ok (Char.code c - Char.code '0')
    | 'a' .. 'f' as c -> Ok (Char.code c - Char.code 'a' + 10)
    | 'A' .. 'F' as c -> Ok (Char.code c - Char.code 'A' + 10)
    | c -> Error (`Invalid_hex (Printf.sprintf "unexpected character %C" c))

  let body s =
    if String.length s >= 2 && s.[0] = '0' && s.[1] = 'x' then
      Ok (String.sub s 2 (String.length s - 2))
    else Error (`Invalid_hex "missing 0x prefix")

  let decode s =
    match body s with
    | Error _ as e -> e
    | Ok h ->
        if String.length h mod 2 <> 0 then
          Error (`Invalid_hex "data must have an even number of digits")
        else
          let out = Bytes.create (String.length h / 2) in
          let rec loop i =
            if i = Bytes.length out then Ok (Bytes.unsafe_to_string out)
            else
              match (nibble h.[2 * i], nibble h.[(2 * i) + 1]) with
              | Ok hi, Ok lo ->
                  Bytes.set out i (Char.chr ((hi lsl 4) lor lo));
                  loop (i + 1)
              | (Error _ as e), _ | _, (Error _ as e) -> e
          in
          loop 0

  let encode_quantity z =
    if Z.sign z < 0 then Error (`Invalid_range "quantity is negative")
    else Ok ("0x" ^ Z.format "%x" z)

  let decode_quantity s =
    match body s with
    | Error _ as e -> e
    | Ok "" -> Error (`Non_canonical "empty quantity")
    | Ok h when String.length h > 1 && h.[0] = '0' ->
        Error (`Non_canonical "quantity has leading zeroes")
    | Ok h -> (
        let rec validate i =
          if i = String.length h then Ok ()
          else
            match nibble h.[i] with
            | Ok _ -> validate (i + 1)
            | Error _ as e -> e
        in
        match validate 0 with
        | Error _ as e -> e
        | Ok () -> (
            try Ok (Z.of_string_base 16 h)
            with Invalid_argument _ -> Error (`Invalid_hex "quantity")))
end

module Uint256 = struct
  type t = Z.t

  let modulus = Z.shift_left Z.one 256
  let zero = Z.zero
  let one = Z.one

  let of_z z =
    if Z.sign z < 0 || Z.geq z modulus then
      Error (`Invalid_range "uint256 must be in [0, 2^256)")
    else Ok z

  let of_int n = of_z (Z.of_int n)
  let to_z x = x

  let of_quantity s =
    match Hex.decode_quantity s with
    | Error _ as e -> e
    | Ok z -> of_z z

  let to_quantity z = Result.get_ok (Hex.encode_quantity z)
  let compare = Z.compare
  let equal = Z.equal
  let pp ppf z = Format.pp_print_string ppf (to_quantity z)
end

module Chain_id = struct
  type t = Z.t

  let of_z z =
    match Uint256.of_z z with
    | Ok z when Z.sign z > 0 -> Ok z
    | Ok _ -> Error (`Invalid_range "chain ID must be positive")
    | Error _ as e -> e

  let of_int n = of_z (Z.of_int n)
  let to_z x = x
  let equal = Z.equal
  let pp ppf z = Format.fprintf ppf "%a" Uint256.pp z
end

module Fixed (N : sig
  val length : int
end) =
struct
  type t = string

  let of_bytes s =
    if String.length s = N.length then Ok s
    else Error (`Invalid_length (N.length, String.length s))

  let to_bytes x = x

  let of_hex s =
    match Hex.decode s with
    | Error _ as e -> e
    | Ok b -> of_bytes b

  let to_hex = Hex.encode
  let equal = String.equal
  let compare = String.compare
  let pp ppf x = Format.pp_print_string ppf (to_hex x)
end

module Raw_address = Fixed (struct
  let length = 20
end)

module Address = struct
  include Raw_address

  let length = 20
  let zero = String.make length '\000'

  let checksum_body raw =
    let lower = Hex.encode_raw raw in
    let digest =
      Digestif.KECCAK_256.digest_string lower
      |> Digestif.KECCAK_256.to_raw_string
    in
    String.init 40 (fun i ->
        match lower.[i] with
        | 'a' .. 'f' as c ->
            let byte = Char.code digest.[i / 2] in
            let h = if i mod 2 = 0 then byte lsr 4 else byte land 0x0f in
            if h >= 8 then Char.uppercase_ascii c else c
        | c -> c)

  let to_checksum t = "0x" ^ checksum_body t

  let of_hex s =
    let raw_result = Hex.decode s in
    match raw_result with
    | Error _ as e -> e
    | Ok raw -> (
        match of_bytes raw with
        | Error _ as e -> e
        | Ok t ->
            let body = String.sub s 2 (String.length s - 2) in
            let has_lower = ref false and has_upper = ref false in
            String.iter
              (function
                | 'a' .. 'f' -> has_lower := true
                | 'A' .. 'F' -> has_upper := true
                | _ -> ())
              body;
            if (not !has_lower) || not !has_upper then Ok t
            else if String.equal body (checksum_body t) then Ok t
            else Error `Checksum_mismatch)

  let to_hex = Hex.encode
end

module Hash = struct
  include Fixed (struct
    let length = 32
  end)

  let length = 32
end

module Storage_key = Fixed (struct
  let length = 32
end)

module Signature = struct
  type t = { y_parity : int; r : Z.t; s : Z.t }

  let curve_order =
    Z.of_string
      "115792089237316195423570985008687907852837564279074904382605163141518161494337"

  let half_curve_order = Z.div curve_order (Z.of_int 2)

  let make ~y_parity ~r ~s =
    if y_parity <> 0 && y_parity <> 1 then
      Error (`Invalid_range "signature y parity must be 0 or 1")
    else if Z.sign r <= 0 || Z.geq r curve_order then
      Error (`Invalid_range "signature r is not in [1, n)")
    else if Z.sign s <= 0 || Z.geq s curve_order then
      Error (`Invalid_range "signature s is not in [1, n)")
    else if Z.gt s half_curve_order then
      Error (`Non_canonical "signature s is not low")
    else Ok { y_parity; r; s }

  let of_bytes ~y_parity b =
    if String.length b <> 64 then Error (`Invalid_length (64, String.length b))
    else
      make
        ~y_parity
        ~r:(z_of_be (String.sub b 0 32))
        ~s:(z_of_be (String.sub b 32 32))

  let y_parity t = t.y_parity
  let r t = t.r
  let s t = t.s

  let to_bytes t =
    Result.get_ok (be_of_z ~len:32 t.r) ^ Result.get_ok (be_of_z ~len:32 t.s)

  let equal a b = a.y_parity = b.y_parity && Z.equal a.r b.r && Z.equal a.s b.s

  let pp ppf t =
    Format.fprintf
      ppf
      "{y_parity=%d; r=0x%s; s=0x%s}"
      t.y_parity
      (Z.format "%x" t.r)
      (Z.format "%x" t.s)
end
