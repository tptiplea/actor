(* The type of OMQ_socket identities *)
type omq_socket_id_t
type omq_msg_t

val omq_socket_id_t_to_string :  omq_socket_id_t -> string
val string_to_omq_socket_id_t : string -> omq_socket_id_t
val omq_msg_t_to_string : omq_msg_t -> string
val string_to_omq_msg_t : string -> omq_msg_t

type 'a omq_socket_t

(* Send a message, with block depending on socket kind *)
val send_msg : ?block:bool -> [<`DEALER | `REP | `REQ] omq_socket_t -> omq_msg_t -> unit Lwt.t

(* Send a message with a ROUTER socket, need id *)
val send_msg_with_id : [`ROUTER] omq_socket_t -> omq_socket_id_t -> omq_msg_t -> unit Lwt.t

(* Recv the message *)
val recv_msg : [<`DEALER | `REP | `REQ] omq_socket_t -> omq_msg_t Lwt.t

(* Recv the message with the id as well. NOTE: Only works on ROUTER sockets *)
val recv_msg_with_id : [`ROUTER] omq_socket_t -> (omq_socket_id_t * omq_msg_t) Lwt.t

(* Bind a local address *)
val bind_local : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> Pcl_bindings.local_sckt_t -> unit Lwt.t

(* deallocate a local address *)
val deallocate_local : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> Pcl_bindings.local_sckt_t -> unit Lwt.t

(* Connect to a remote address *)
val connect_to_remote : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> Pcl_bindings.remote_sckt_t -> Pcl_bindings.local_sckt_t Lwt.t

(* Create *)
val _internal_create_rep : unit -> [`REP] omq_socket_t

val _internal_create_req : unit -> [`REQ] omq_socket_t

val _internal_create_dealer : unit -> [`DEALER] omq_socket_t

val _internal_create_router : unit -> [`ROUTER] omq_socket_t

(* Close *)
val _internal_close : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> unit

(* Setter/getters *)
val set_send_high_water_mark : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> int -> unit
val set_recv_high_water_mark : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> int -> unit
val get_send_high_water_mark : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> int
val get_recv_high_water_mark : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> int
val set_send_timeoutms : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> int -> unit
val set_recv_timeoutms : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> int -> unit
val set_identity : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> omq_socket_id_t -> unit
val get_identity : [<`DEALER | `REP | `REQ | `ROUTER] omq_socket_t -> omq_socket_id_t
