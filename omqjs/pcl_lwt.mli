(* Wrapper with promises around pcl_bindings *)

val promise_start_comm_layer : string -> string Lwt.t

val promise_bind_address : Pcl_bindings.local_sckt_t -> unit Lwt.t

val promise_deallocate_address : Pcl_bindings.local_sckt_t -> unit Lwt.t

val promise_connect_to_address : Pcl_bindings.remote_sckt_t -> Pcl_bindings.local_sckt_t Lwt.t

val promise_send_msg : Pcl_bindings.local_sckt_t -> Pcl_bindings.remote_sckt_t -> Pcl_bindings.msg_t -> unit Lwt.t

val promise_recv_msg : Pcl_bindings.local_sckt_t -> (Pcl_bindings.remote_sckt_t * Pcl_bindings.msg_t) Lwt.t
