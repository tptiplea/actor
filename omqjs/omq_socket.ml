open Omq_types
open Pcl_bindings
open Pcl_lwt

type omq_socket_id_t = string
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
  mutable out_msg_q : (msg_t * ((unit Lwt.t) * (unit Lwt.u))) list;
  (* the queue of incoming msgs for this socket*)
  mutable in_msg_q : (remote_sckt_t * local_sckt_t * omq_socket_id_t * msg_t) list;
  (* the queue of promises for messages *)
  mutable in_cons_q : ((omq_socket_id_t * msg_t) Lwt.t * (omq_socket_id_t * msg_t) Lwt.u) list;
}

(* Sweeps through the queues and removes resolved/rejected promises *)
let _rmv_nonpending_promises sckt =
  sckt.out_msg_q <- List.filter (fun (_, (p, _)) -> Lwt.is_sleeping p) sckt.out_msg_q;
  sckt.in_cons_q <- List.filter (fun (p, _) -> Lwt.is_sleeping p) sckt.in_cons_q

(* TODO: This is choosing one at random for now *)
(* If no services connected, it either queues the message or  *)
let _round_robin_send_msg ?(block=true) sckt msg =
  let cncts = sckt.connections_to in
  match RemoteSocketMap.is_empty cncts with
  | true -> (
      if block then (
        let _ = _rmv_nonpending_promises sckt in
        let out_q_l = List.length sckt.out_msg_q in
        if out_q_l >= sckt.send_high_water_mark
        then OMQ_Exception "Cannot queue for send - reached send_high_water_mark!" |> Lwt.fail
        else
          let promise, resolver = Lwt.task () in
          let _ = sckt.out_msg_q <- (msg, (promise, resolver))::sckt.out_msg_q in
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
  match sckt.in_msg_q with
    (_, _, id, msg)::rest_in_q -> sckt.in_msg_q <- rest_in_q; Lwt.return (id, msg)
  | [] ->
    let _ = _rmv_nonpending_promises sckt in
    let in_cons_q_l = List.length sckt.in_cons_q in
    if in_cons_q_l >= sckt.recv_high_water_mark
    then OMQ_Exception "Cannot wait for message -- reached recv_high_water_mark" |> Lwt.fail
    else
      let promise, resolver = Lwt.task () in
      sckt.in_cons_q <- (promise, resolver)::sckt.in_cons_q;
      Omq_utils.add_mstimeout_to_promise sckt.send_timeout_ms resolver (OMQ_Exception "TIMEOUT waiting for message!");
      promise

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
  let msg = Json.output (sckt.identity, msg) |> Js.to_string |> string_to_msg_t in
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
