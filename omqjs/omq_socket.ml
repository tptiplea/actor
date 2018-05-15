open Omq_types
open Pcl_bindings
open Pcl_lwt

type omq_socket_id_t = string
type omq_msg_t = Payload of string
let omq_msg_t_to_string (Payload x) = x
let string_to_omq_msg_t x = Payload x
let omq_socket_id_t_to_string x = x
let string_to_omq_socket_id_t x = x
module OmqSocketIdMap = Map.Make(String)

type operation_t =
    Send of local_sckt_t * remote_sckt_t
  | Recv of remote_sckt_t * local_sckt_t

type omq_socket_t = {
  (* the kind of socket *)
  kind : omq_sckt_kind;
  (* the identity of the socket, created randomly, or can be set *)
  mutable identity : omq_socket_id_t;
  (* which unix_sockets we are listening on with this omq_socket *)
  mutable listening_on : LocalSocketSet.t;
  (* map from remote -> local socket *)
  mutable connections_to : local_sckt_t RemoteSocketMap.t;
  (* map from remote idenitities to lower connections *)
  mutable routing_table : (local_sckt_t * remote_sckt_t) OmqSocketIdMap.t;
  (* timeout for send operation *)
  mutable send_timeout_ms : int;
  (* timeout for a recv operation *)
  mutable recv_timeout_ms : int;
  (* the queue size for outgoing operations *)
  mutable send_high_water_mark : int;
  (* the queue size of recv operations *)
  mutable recv_high_water_mark : int;
  (* the last successful operation *)
  mutable last_operation : operation_t option;
  (* the queue of outgoing msgs that were not sent because no service available, and their resolvers *)
  mutable out_msg_q : (msg_t * ((unit Lwt.t) * (unit Lwt.u))) Queue.t;
  (* the queue of incoming msgs for this socket*)
  mutable in_msg_q : (remote_sckt_t * local_sckt_t * omq_socket_id_t * omq_msg_t) Queue.t;
  (* the queue of promises for messages *)
  mutable in_cons_q : ((omq_socket_id_t * omq_msg_t) Lwt.t * (omq_socket_id_t * omq_msg_t) Lwt.u) Queue.t;
}

(* Sweeps through the queues and removes resolved/rejected promises. *)
(*  *)

let _rmv_nonpending_promises_in_prefix sckt =
  Omq_utils.trim_queue_prefix (fun (p, _) -> not (Lwt.is_sleeping p)) sckt.in_cons_q;
  Omq_utils.trim_queue_prefix (fun (_, (p, _)) -> not (Lwt.is_sleeping p)) sckt.out_msg_q

let _rmv_nonpending_consumers_if_needed sckt =
  _rmv_nonpending_promises_in_prefix sckt;
  if Queue.length sckt.in_cons_q >= sckt.recv_high_water_mark
  then sckt.in_cons_q <- Omq_utils.queue_filter (fun (p, _) -> not (Lwt.is_sleeping p)) sckt.in_cons_q

let _rmv_nonpending_outgoing_msgs_if_needed sckt =
  _rmv_nonpending_promises_in_prefix sckt;
  if Queue.length sckt.out_msg_q >= sckt.send_high_water_mark
  then sckt.out_msg_q <- Omq_utils.queue_filter (fun (_, (p, _)) -> not (Lwt.is_sleeping p)) sckt.out_msg_q

let _pack_to_raw_msg : omq_socket_id_t -> omq_msg_t -> Pcl_bindings.msg_t =
  fun id (Payload msg) ->
    Json.output (id, Payload msg) |> Js.to_string |> string_to_msg_t


let _unpack_raw_msg : Pcl_bindings.msg_t -> (omq_socket_id_t * omq_msg_t) =
  function raw_msg ->
    let (id, Payload str_msg) = raw_msg |> Pcl_bindings.msg_t_to_string |> Js.string |> Json.unsafe_input in
    (id, Payload str_msg)


let _on_msg_to_sckt sckt remote local msg =
  if not (LocalSocketSet.mem local sckt.listening_on)
  then
    print_string "WARN: omq_socket.ml; got message on socket not listening on just yet! Dropping it!\n"
  else (
    (* first see if anyone waiting for a message *)
    _rmv_nonpending_promises_in_prefix sckt;
    let (from_omq_id, msg) = _unpack_raw_msg msg in
    if not (Queue.is_empty sckt.in_cons_q)
    then ( (* noone waiting for a message, add it to the msg queue *)
      match Queue.length sckt.in_msg_q < sckt.recv_high_water_mark with
        true -> Queue.add (remote, local, from_omq_id, msg) sckt.in_msg_q (*queue the message*)
      | false -> print_string "WARN: Messaged dropped, reached high water mark!!\n"
    ) else (
      let _, resolver = Queue.pop sckt.in_cons_q in
      match Omq_utils.safe_resolve_promise resolver (from_omq_id, msg) with
        true -> () (* all went ok *)
      | _ -> print_string "ERROR: Could not resolve in_cons_q promise although it should still be pending!!\n"
    )
  )

let _on_connection_to sckt local remote connected =
  match connected with
    true -> (
      print_string "INFO: New remote connected to sckt: \n";
      if not (LocalSocketSet.mem local sckt.listening_on)
      then print_string "WARN: The local address is not yet acknowledged by the OMQSocket";
      sckt.connections_to <- RemoteSocketMap.add remote local sckt.connections_to
    )
  | false -> (
      print_string "WARN: Remote disconnected from sckt\n";
      if (not (RemoteSocketMap.mem remote sckt.connections_to))
      then print_string "WARN: The remote that disconnected is not known by the OMQSocket!"
      else sckt.connections_to <- RemoteSocketMap.remove remote sckt.connections_to
    )

let _listen_on_local sckt local =
  if LocalSocketSet.mem local sckt.listening_on
  then Printf.printf "ERROR: Already listening on local %s\n" (local_sckt_t_to_string local)
  else (
    sckt.listening_on <- LocalSocketSet.add local sckt.listening_on;
    Printf.printf "INFO: %s local was bound to socket with id %s\n"
      (Pcl_bindings.local_sckt_t_to_string local) (sckt.identity)
  )

let _stop_listening_on_local sckt local =
  if not (LocalSocketSet.mem local sckt.listening_on)
  then Printf.printf "ERROR: Wasn't listening on local %s\n!!" (local_sckt_t_to_string local)
  else (
    sckt.listening_on <- LocalSocketSet.remove local sckt.listening_on;
    Printf.printf "INFO: %s local was deallocated from socket with id %s\n"
      (Pcl_bindings.local_sckt_t_to_string local) (sckt.identity);
  )

let bind_local sckt local =
  let%lwt () = Pcl_lwt.promise_bind_address
      local (_on_msg_to_sckt sckt) (_on_connection_to sckt)
  in
  Lwt.return (_listen_on_local sckt local)

let deallocate_local sckt local =
  _stop_listening_on_local sckt local;
  Pcl_lwt.promise_deallocate_address local

let connect_to_remote sckt remote =
  let%lwt local = Pcl_lwt.promise_connect_to_address
      remote (_on_msg_to_sckt sckt) (_on_connection_to sckt) in
  Printf.printf "INFO: %s omqsocket is connected to remote %s, listening on local %s\n"
    sckt.identity
    (Pcl_bindings.remote_sckt_t_to_string remote) (Pcl_bindings.local_sckt_t_to_string local);
  sckt.listening_on <- LocalSocketSet.add local sckt.listening_on;
  Lwt.return (local)

(* TODO: This is choosing one at random for now *)
(* If no services connected, it either queues the message or  *)
let _round_robin_send_msg ?(block=true) sckt msg =
  let cncts = sckt.connections_to in
  match RemoteSocketMap.is_empty cncts with
  | true -> (
      if block then (
        _rmv_nonpending_outgoing_msgs_if_needed sckt;
        if Queue.length sckt.out_msg_q >= sckt.send_high_water_mark
        then OMQ_Exception "Cannot queue for send - reached send_high_water_mark!" |> Lwt.fail
        else
          let promise, resolver = Lwt.task () in
          let _ = Queue.add (msg, (promise, resolver)) sckt.out_msg_q in
          let _ = Omq_utils.add_mstimeout_to_promise sckt.send_timeout_ms resolver
              (OMQ_Exception "TIMEDOUT trying to send message!")
          in promise
      ) else
        Lwt.fail (OMQ_Exception "No connected services to send msg to!!")
    )
  | false -> (* choose a random service to send it to *)
    let rand_ind = ref (RemoteSocketMap.cardinal cncts |> Random.int) in
    let remote = ref (RemoteSocketMap.choose cncts |> fst) in
    let local = ref (RemoteSocketMap.find !remote cncts) in
    let _ = RemoteSocketMap.iter (fun r l ->
        (if !rand_ind = 0 then (remote := r; local := l));
        rand_ind := !rand_ind - 1
      ) cncts in
    sckt.last_operation <- Some (Send (!local, !remote));
    promise_send_msg !local !remote msg

(* Recv message, always blocking, but with timeout *)
let _recv_msg_with_id_any_sckt sckt =
  if (Queue.is_empty sckt.in_msg_q)
  then (
    let remote, local, id, msg = Queue.pop sckt.in_msg_q in
      sckt.last_operation <- Some (Recv (remote, local));
      Lwt.return (id, msg)
  )
  else (
    _rmv_nonpending_consumers_if_needed sckt;
    if Queue.length sckt.in_cons_q >= sckt.recv_high_water_mark
    then OMQ_Exception "Cannot wait for message -- reached recv_high_water_mark" |> Lwt.fail
    else
      let promise, resolver = Lwt.task () in
      Queue.add (promise, resolver) sckt.in_cons_q;
      Omq_utils.add_mstimeout_to_promise sckt.send_timeout_ms resolver (OMQ_Exception "TIMEOUT waiting for message!");
      promise
  )

let recv_msg_with_id sckt =
  match sckt.kind with
    ROUTER -> _recv_msg_with_id_any_sckt sckt
  | k -> OMQ_Exception ("Cannot get identity from socket of kind " ^ Omq_types.omq_sckt_kind_to_string k) |> Lwt.fail

let recv_msg sckt =
  let%lwt _, msg = _recv_msg_with_id_any_sckt sckt in
  Lwt.return msg

(* Send a message, either blocking or non-blocking *)
let send_msg ?(block=true) sckt ?dest_omq_id msg =
  (* the message will contain the id (mine) as the first frame *)
  let msg = _pack_to_raw_msg sckt.identity msg in
  match sckt.kind with
    REQ -> (
      match sckt.last_operation with
        Some (Send (_, _)) -> OMQ_Exception "Called send twice in a row on a REQ socket" |> Lwt.fail
      | _ -> _round_robin_send_msg ~block sckt msg (* send in round robin style to one of the connected services *)
    )
  | REP -> (
      match sckt.last_operation with
        Some (Recv (remote, local)) -> (
          match sckt.connections_to |> RemoteSocketMap.mem remote with
            true -> sckt.last_operation <- Some (Send (local, remote)); promise_send_msg local remote msg
          | false -> Lwt.return () (*silently discard if peer is not here, as in docs *)
        )
      | Some (Send (_, _)) -> OMQ_Exception "Called send twice in a row on a REP socket" |> Lwt.fail
      | None -> OMQ_Exception "Called send before any recv on a REP socket" |> Lwt.fail
    )
  | DEALER -> _round_robin_send_msg ~block sckt msg (* send in round robin style *)
  | ROUTER -> (
      match dest_omq_id with
        None -> OMQ_Exception "Must provide OMQ Socket Identity when sending on Router socket" |> Lwt.fail
      | Some dest_omq_id ->
        let connection = OmqSocketIdMap.find_opt dest_omq_id sckt.routing_table in
        match connection with
          Some (local, remote) -> (
            sckt.last_operation <- Some (Send (local, remote));
            Pcl_lwt.promise_send_msg local remote msg
          )
        (* does not exist anymore, discard the message silently, as in the OMQ doc *)
        | None -> Lwt.return ()
    )
