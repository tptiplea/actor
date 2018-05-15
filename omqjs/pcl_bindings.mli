(** OCaml bindings to the JS api of the peer communication layer *)
(* Opaque types to enforce the order of arguments *)
type msg_t
type local_sckt_t
type remote_sckt_t
type fail_reason_t

val string_to_msg_t : string -> msg_t
val msg_t_to_string : msg_t -> string
val local_sckt_t_to_string : local_sckt_t -> string
val string_to_local_sckt_t : string -> local_sckt_t
val remote_sckt_t_to_string : remote_sckt_t -> string
val string_to_remote_sckt_t : string -> remote_sckt_t
val fail_reason_t_to_string : fail_reason_t -> string
val string_to_fail_reason_t : string -> fail_reason_t

module LocalSocketSet : Set.S with type elt = local_sckt_t
module RemoteSocketSet : Set.S with type elt = remote_sckt_t
module LocalSocketMap : Map.S with type key = local_sckt_t
module RemoteSocketMap : Map.S with type key = remote_sckt_t

(** A failure callback is given a stringified reason for the failure *)
type fail_callback_t = fail_reason_t -> unit

(** A callback called with a message *)
type on_msg_callback_t = remote_sckt_t -> local_sckt_t -> msg_t -> unit

(** A callback for when a remote socket is either connected to or disconnected from the local socket *)
type on_connection_to_callback_t = local_sckt_t -> remote_sckt_t -> bool -> unit

(**
   Function that starts the communication layer and calls the callback when
   connected to the signalling server.
   The callback is passed the Unique ID of this peer.
   Needs the signalling server URL as the first argument.
*)
val pcl_start_comm_layer : string -> (string -> unit) -> fail_callback_t -> unit


(**
   Function that binds an address (must be unique),
   calling the first callback on success, or the other on failure.
*)
val pcl_bind_address : local_sckt_t -> on_msg_callback_t -> on_connection_to_callback_t -> (unit -> unit) -> fail_callback_t -> unit


(**
   Function that unbinds an address (must be already registered), similar to bind.
*)
val pcl_deallocate_address : local_sckt_t -> (unit -> unit) -> fail_callback_t -> unit

(**
   Function that connects to an address. It calls the on_success_callback with
   the unixsocket_id we are connected with to that address, or the
   failure_callback if some error occurred.
*)
val pcl_connect_to_address : remote_sckt_t -> on_msg_callback_t -> on_connection_to_callback_t -> (local_sckt_t -> unit) -> fail_callback_t -> unit

(**
   Function that sends a message from a unixsocket A to another unixsocket B.
   It must be that A and B are connected, either by A being the result of a
   connect_to_address(B) operation (then this is a client), or B is a client
   that connected to our socket A (then this is the server).
   pcl_send_msg unixsocket_A unixsocket_B msg on_success_callback on_failure_callback
*)
val pcl_send_msg : local_sckt_t -> remote_sckt_t -> msg_t -> (unit -> unit) -> fail_callback_t -> unit
