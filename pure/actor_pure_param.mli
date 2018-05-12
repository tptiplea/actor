(** [ Model Parallel ] Parameter server module  *)

open Actor_pure_types



(** core interfaces to parameter server *)

module Internal (KeyValueTypeSpecifier: KeyValueTypeSig) : sig
  type key_t = KeyValueTypeSpecifier.key_t
  type value_t = KeyValueTypeSpecifier.value_t
  type vars_t = (key_t * value_t) list

  (* context type, duplicate from Actor_pure_types *)
  type param_context = Actor_pure_types.param_context

  type barrier =
    | ASP    (* Asynchronous Parallel *)
    | BSP    (* Bulk Synchronous Parallel *)
    | SSP    (* Stale Synchronous Parallel *)
    | PSP    (* Probabilistic Synchronous Parallel *)


val start : ?barrier:barrier -> string -> string -> unit Lwt.t
(** start running the model loop *)

val register_barrier : (param_context ref -> int * (string list)) -> unit
(** register user-defined barrier function at p2p server *)

val register_schedule : (string list -> (string * (key_t * value_t) list) list) -> unit
(** register user-defined scheduler *)

val register_pull : ((key_t * value_t) list -> (key_t * value_t) list) -> unit
(** register user-defined pull function executed at master *)

val register_push : ((string -> (key_t * value_t) list -> (key_t * value_t) list)) -> unit
(** register user-defined push function executed at worker *)

val register_stop : (param_context ref -> bool) -> unit
(** register stopping criterion function *)

val get : key_t -> (value_t * int) Lwt.t
(** given a key, get its value and timestamp *)

val set : key_t -> value_t -> unit Lwt.t
(** given a key, set its value at master *)

val keys : unit -> key_t list
(** FIXME: reture all the keys in a parameter server *)

val worker_num : unit -> int
(** return the number of workders, only work at server side *)
end
