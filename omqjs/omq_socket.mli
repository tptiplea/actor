(* The type of OMQ_socket identities *)
type omq_socket_id_t

val omq_socket_id_t_to_string :  omq_socket_id_t -> string
val string_to_omq_socket_id_t : string -> omq_socket_id_t

type omq_socket_t

(* Send a message, with block depending on socket kind *)
val send_msg : ?block:bool -> omq_socket_t -> ?dest_omq_id:omq_socket_id_t -> Pcl_bindings.msg_t -> unit Lwt.t

(* Recv the message *)
val recv_msg : omq_socket_t -> Pcl_bindings.msg_t Lwt.t
(* Recv the message with the id as well. NOTE: Only works on ROUTER sockets *)
val recv_msg_with_id : omq_socket_t -> (omq_socket_id_t * Pcl_bindings.msg_t) Lwt.t

    (*TODO: remove *)
type operation_t =
    Send of Pcl_bindings.local_sckt_t * Pcl_bindings.remote_sckt_t
  | Recv of Pcl_bindings.remote_sckt_t * Pcl_bindings.local_sckt_t
