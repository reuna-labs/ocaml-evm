type response = Return of Yojson.Safe.t | Raise of Error.t

type expectation = {
  method_ : string;
  params : Yojson.Safe.t list;
  response : response;
}

type t = {
  mutable expectations : expectation list;
  mutable calls : (string * Yojson.Safe.t list) list;
}

let create expectations = { expectations; calls = [] }
let remaining t = List.length t.expectations
let calls t = List.rev t.calls

let request t ~method_ ~params =
  t.calls <- (method_, params) :: t.calls;
  match t.expectations with
  | [] -> Error (Error.Transport ("unexpected mock call: " ^ method_))
  | expected :: rest ->
      if String.equal expected.method_ method_ && expected.params = params then (
        t.expectations <- rest;
        match expected.response with
        | Return value -> Ok value
        | Raise error -> Error error)
      else
        Error
          (Error.Transport
             (Printf.sprintf
                "mock mismatch: expected %s, received %s"
                expected.method_
                method_))

module Provider = struct
  type nonrec t = t
  type 'a io = 'a

  let return x = x
  let bind x f = f x
  let request = request
end
