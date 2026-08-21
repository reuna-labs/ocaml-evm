type 'a t = {
  name : string;
  params : Yojson.Safe.t list;
  decode : Yojson.Safe.t -> ('a, string) result;
}

let make ~name ?(params = []) decode = { name; params; decode }
let name t = t.name
let params t = t.params
let decode t = t.decode
