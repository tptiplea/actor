open Omq_types
open Pcl_bindings

type omq_socket_id_t = string
type omq_msg_t = Payload of string
let omq_msg_t_to_string (Payload x) = x
let string_to_omq_msg_t x = Payload x
let omq_socket_id_t_to_string x = x
let string_to_omq_socket_id_t x = x
module OmqSocketIdMap = Map.Make(String)

type operation_t =
    None
  | Send of local_sckt_t * remote_sckt_t
  | Recv of remote_sckt_t * local_sckt_t

type sckt_state_t =
    NotBlocked of operation_t (* the last operation *)
  | BlockedSend of operation_t * (msg_t * (unit Lwt.u)) (* an outstanding msg *)
  | BlockedRecv of operation_t * ((omq_socket_id_t * omq_msg_t) Lwt.u) (* a consumer waiting for a message *)

let _last_op_from_sckt_state = function
    NotBlocked lop -> lop
  | BlockedSend (lop, _) -> lop
  | BlockedRecv (lop, _) -> lop

(**
   The socket can only be in a blocking state if it is waiting to send a message,
   or receive one. This can only happen on receive for any socket,
   or on send ~block:true for REQ or DEALER (for the other two, if it cannot send, it drops it!).
   If it is in a blocking state, then it cannot perform any other operation!
   So in that case, it throws an error if someone tries to do another operation on it.
   *)
type omq_socket_t = {
  (* the kind of socket *)
  kind : omq_sckt_kind;
  (* whether it is open *)
  mutable is_open : bool;
  (* whether it is in a blocking state *)
  mutable state : sckt_state_t;
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
  (* the queue of incoming msgs for this socket*)
  mutable in_msg_q : (remote_sckt_t * local_sckt_t * omq_socket_id_t * omq_msg_t) Queue.t;
  (* the queue of promises for messages *)
}

let _ensure_not_blocked_and_open sckt =
  if not sckt.is_open
  then OMQ_Exception "ERROR: Operation on closed socket" |> raise
  else match sckt.state with
      NotBlocked _ -> ()
    | BlockedRecv _ -> OMQ_Exception "ERROR: Omq socket is blocked in a RECV operation" |> raise
    | BlockedSend _ -> OMQ_Exception "ERROR: Omq socket is blocked in a SEND operation" |> raise

let _pack_to_raw_msg : omq_socket_id_t -> omq_msg_t -> Pcl_bindings.msg_t =
  fun id (Payload msg) ->
    Json.output (id, Payload msg) |> Js.to_string |> string_to_msg_t


let _unpack_raw_msg : Pcl_bindings.msg_t -> (omq_socket_id_t * omq_msg_t) =
  function raw_msg ->
    let (id, Payload str_msg) = raw_msg |> Pcl_bindings.msg_t_to_string |> Js.string |> Json.unsafe_input in
    (id, Payload str_msg)

let _make_with_timeout_blocking_promise sckt ~no_timeout_promise ~timeout_ms
    ~blocked_state ~unblocked_state ~timeout_during =
  sckt.state <- blocked_state;
  let with_timeout_promise =
    Omq_utils.add_on_mstimeout_callback_to_promise_then_exc
      timeout_ms
      no_timeout_promise
      (* on_timeout_callback -> before we let the client know about the timeout, update the socket state *)
      (fun () -> sckt.state <- unblocked_state)
      (OMQ_Exception ("TIMEOUT DURING: " ^ timeout_during))
  in
  with_timeout_promise

let _on_msg_to_sckt sckt remote local msg =
  (
    if not (LocalSocketSet.mem local sckt.listening_on) then
      (* This should only happen on a connect call, in which case messages *)
      print_string "WARN: omq_socket.ml; got message on socket not listening on just yet!\n";
  );
  (* first see if anyone waiting for a message *)
  let (from_omq_id, msg) = _unpack_raw_msg msg in
  match sckt.state with
    NotBlocked _
  | BlockedSend _ -> ( (* noone waiting for a message, add it to the msg queue *)
      match Queue.length sckt.in_msg_q < sckt.recv_high_water_mark with
        true -> Queue.add (remote, local, from_omq_id, msg) sckt.in_msg_q (*queue the message*)
      | false -> print_string "WARN: Messaged dropped, reached recv high water mark!!\n"
    )
  | BlockedRecv (_, resolver) -> (
      (* update the state *)
      sckt.routing_table <- OmqSocketIdMap.add from_omq_id (local, remote) sckt.routing_table;
      sckt.state <- NotBlocked (Recv (remote, local));
      Omq_utils.resolve_promise resolver (from_omq_id, msg)
    )


let _on_connection_to sckt local remote connected =
  match connected with
    true -> (
      Printf.printf "INFO: New remote (%s) connected to sckt\n" (Pcl_bindings.remote_sckt_t_to_string remote);
      if not (LocalSocketSet.mem local sckt.listening_on)
      then print_string "WARN: The local address is not yet acknowledged by the OMQSocket";
      sckt.connections_to <- RemoteSocketMap.add remote local sckt.connections_to;
      (* need to send the outstanding msg if there is any *)
      match sckt.state with
        NotBlocked _
      | BlockedRecv _ -> () (* nothing to do in these two cases *) (*TODO:TODO:TODO *)
      | BlockedSend (_, (msg, resolver)) ->
        Lwt.ignore_result (
          let%lwt () = Pcl_lwt.promise_send_msg local remote msg in
          sckt.state <- NotBlocked (Send (local, remote));
          Omq_utils.resolve_promise resolver ();
          Lwt.return_unit
        )
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
  _ensure_not_blocked_and_open sckt;
  let%lwt () = Pcl_lwt.promise_bind_address
      local (_on_msg_to_sckt sckt) (_on_connection_to sckt)
  in
  Lwt.return (_listen_on_local sckt local)

let deallocate_local sckt local =
  _ensure_not_blocked_and_open sckt;
  _stop_listening_on_local sckt local;
  Pcl_lwt.promise_deallocate_address local

let connect_to_remote sckt remote =
  _ensure_not_blocked_and_open sckt;
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
        let no_timeout_promise, resolver = Lwt.task () in
        let blocked_state = BlockedSend ((_last_op_from_sckt_state sckt.state), (msg, resolver)) in
        let unblocked_state = NotBlocked (_last_op_from_sckt_state sckt.state) in
        let timeout_during = "sending message" in
        let timeout_ms = sckt.send_timeout_ms in
        _make_with_timeout_blocking_promise sckt ~no_timeout_promise
          ~timeout_ms ~blocked_state ~unblocked_state ~timeout_during
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
    sckt.state <- NotBlocked (Send (!local, !remote));
    Pcl_lwt.promise_send_msg !local !remote msg

(* Recv message, always blocking, but with timeout *)
let _recv_msg_with_id_any_sckt sckt =
  if not (Queue.is_empty sckt.in_msg_q)
  then (
    let remote, local, id, msg = Queue.pop sckt.in_msg_q in
    sckt.state <- NotBlocked (Recv (remote, local));
    sckt.routing_table <- OmqSocketIdMap.add id (local, remote) sckt.routing_table;
      Lwt.return (id, msg)
  )
  else (
    (* must block, with timeout, for message to appear *)
    let no_timeout_promise, resolver = Lwt.task () in
    let blocked_state = BlockedRecv ((_last_op_from_sckt_state sckt.state), resolver) in
    let unblocked_state = NotBlocked (_last_op_from_sckt_state sckt.state) in
    let timeout_during = "waiting for message recv" in
    let timeout_ms = sckt.recv_timeout_ms in
    _make_with_timeout_blocking_promise sckt ~no_timeout_promise
      ~timeout_ms ~blocked_state ~unblocked_state ~timeout_during
  )

let recv_msg_with_id sckt =
  _ensure_not_blocked_and_open sckt;
  match sckt.kind with
    ROUTER -> _recv_msg_with_id_any_sckt sckt
  | k -> OMQ_Exception ("Cannot get identity from socket of kind " ^ Omq_types.omq_sckt_kind_to_string k) |> Lwt.fail

let recv_msg sckt =
  _ensure_not_blocked_and_open sckt;
  let%lwt _, msg = _recv_msg_with_id_any_sckt sckt in
  Lwt.return msg

(* Send a message, either blocking or non-blocking *)
let send_msg ?(block=true) sckt ?dest_omq_id msg =
  _ensure_not_blocked_and_open sckt;
  (* the message will contain the id (mine) as the first frame *)
  let msg = _pack_to_raw_msg sckt.identity msg in
  match sckt.kind with
    REQ -> (
      match _last_op_from_sckt_state sckt.state with
        Send (_, _) -> OMQ_Exception "Called send twice in a row on a REQ socket" |> Lwt.fail
      | _ -> _round_robin_send_msg ~block sckt msg (* send in round robin style to one of the connected services *)
    )
  | REP -> (
      match _last_op_from_sckt_state sckt.state with
        Recv (remote, local) -> (
          match sckt.connections_to |> RemoteSocketMap.mem remote with
            true -> sckt.state <- NotBlocked (Send (local, remote)); Pcl_lwt.promise_send_msg local remote msg
          | false -> Lwt.return () (*silently discard if peer is not here, as in docs *)
        )
      | Send (_, _) -> OMQ_Exception "Called send twice in a row on a REP socket" |> Lwt.fail
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
            sckt.state <- NotBlocked (Send (local, remote));
            Pcl_lwt.promise_send_msg local remote msg
          )
        (* does not exist anymore, discard the message silently, as in the OMQ doc *)
        | None -> Lwt.return ()
    )

let set_send_high_water_mark sckt hwm = _ensure_not_blocked_and_open sckt; sckt.send_high_water_mark <- hwm
let get_send_high_water_mark sckt = _ensure_not_blocked_and_open sckt; sckt.send_high_water_mark
let set_recv_high_water_mark sckt hwm = _ensure_not_blocked_and_open sckt; sckt.recv_high_water_mark <- hwm
let get_recv_high_water_mark sckt = _ensure_not_blocked_and_open sckt; sckt.recv_high_water_mark
let set_send_timeoutms sckt tm = _ensure_not_blocked_and_open sckt; sckt.send_timeout_ms <- tm
let set_recv_timeoutms sckt tm = _ensure_not_blocked_and_open sckt; sckt.recv_timeout_ms <- tm
let set_identity sckt id = _ensure_not_blocked_and_open sckt; sckt.identity <- id
let get_identity sckt = _ensure_not_blocked_and_open sckt; sckt.identity

let _internal_create k = {
  kind = k;
  is_open = true;
  state = NotBlocked None;
  identity = Pcl_bindings.pcl_util_rand_str 20; (* random identity by default *)
  listening_on = LocalSocketSet.empty;
  connections_to = RemoteSocketMap.empty;
  routing_table = OmqSocketIdMap.empty;
  send_timeout_ms = Pervasives.max_int; (* do not timeout by default *)
  recv_timeout_ms = Pervasives.max_int;
  send_high_water_mark = 10_000;
  recv_high_water_mark = 10_000;
  in_msg_q = Queue.create ();
}

let _internal_close sckt =
  if not sckt.is_open
  then OMQ_Exception "ERROR: OMQ socket already closed!" |> raise
  else sckt.is_open <- false
