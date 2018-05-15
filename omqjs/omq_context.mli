type omq_context_t

val create : unit -> omq_context_t
val terminate : omq_context_t -> unit

val create_socket : omq_context_t -> Omq_types.omq_sckt_kind -> Omq_socket.omq_socket_t
val close_socket : omq_context_t -> Omq_socket.omq_socket_t -> unit 
