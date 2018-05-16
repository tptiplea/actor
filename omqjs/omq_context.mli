type omq_context_t

(* Given a string for the signalling server url, start the comm layer!
   Return the unique peer id with the server, and the context *)
val create : string -> (string * omq_context_t) Lwt.t
val terminate : omq_context_t -> unit

val create_socket : omq_context_t -> Omq_types.omq_sckt_kind -> Omq_socket.omq_socket_t
val close_socket : omq_context_t -> Omq_socket.omq_socket_t -> unit
