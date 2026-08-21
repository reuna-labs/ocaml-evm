(** EIP-1193's provider boundary is a method name plus JSON-compatible params,
    returning the JSON-compatible result or a structured provider error. *)

module type S = Provider.S

module Make = Provider.Make
