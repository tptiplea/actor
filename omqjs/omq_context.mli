type omq_context_t

(* Given a string for the signalling server url, start the comm layer!
   Return the unique peer id with the server, and the context *)
val create : string -> (string * omq_context_t) Lwt.t
val terminate : omq_context_t -> unit

val create_rep_socket : omq_context_t -> [`REP] Omq_socket.omq_socket_t

val create_req_socket : omq_context_t -> [`REQ] Omq_socket.omq_socket_t

val create_dealer_socket : omq_context_t -> [`DEALER] Omq_socket.omq_socket_t

val create_router_socket : omq_context_t -> [`ROUTER] Omq_socket.omq_socket_t

val close_rep_socket : omq_context_t -> [`REP] Omq_socket.omq_socket_t -> unit

val close_req_socket : omq_context_t -> [`REQ] Omq_socket.omq_socket_t -> unit

val close_dealer_socket : omq_context_t -> [`DEALER] Omq_socket.omq_socket_t -> unit

val close_router_socket : omq_context_t -> [`ROUTER] Omq_socket.omq_socket_t -> unit
