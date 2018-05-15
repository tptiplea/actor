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
  (* map from remote idenitities to lower connections *)
  mutable routing_table : (local_sckt_t * remote_sckt_t) OmqSocketIdMap.t;
  (* timeout for send operation *)
  mutable send_timeout : int;
  (* timeout for a recv operation *)
  mutable recv_timeout : int;
  (* the queue size of recv operations *)
  mutable recv_high_water_mark : int;
  (* the last successful operation *)
  mutable last_operation : operation_t option;
(* the queue of outgoing msgs that we're not sent because no service available *)
  mutable out_queue : (msg_t * (unit Lwt.u)) list
}

(* Get all remotes connected to this local socket *)
let _get_connected_to local =
  let remotes = ref RemoteSocketSet.empty in
  let collect = (fun remote -> remotes := RemoteSocketSet.add remote !remotes) in
  let _ = pcl_get_all_remote_sockets local collect in
  !remotes

let _get_all_connections sckt =
  let connections = ref RemoteSocketMap.empty in
  let _ = LocalSocketSet.iter (fun local ->
      RemoteSocketSet.iter (fun remote ->
          ignore (RemoteSocketMap.add remote local !connections)
        ) (_get_connected_to local)
    ) sckt.listening_on in
  !connections

(* TODO: This is choosing one at random for now *)
let _round_robin_send_msg ?(block=true) sckt msg =
  let cncts = _get_all_connections sckt in
  match RemoteSocketMap.is_empty cncts with
  | true -> (
      if block then (
        let promise, resolver = Lwt.task () in
        let _ = sckt.out_queue <- (msg, resolver)::sckt.out_queue in
        let _ = Lwt_timeout.create sckt.send_timeout (fun () ->
            Lwt.wakeup_later_exn resolver (OMQ_Exception "TIMEDOUT trying to send message!")
          ) |> Lwt_timeout.start in
        promise
      ) else
        Lwt.fail (OMQ_Exception "No connected services to send msg to!!")
    )
  | false ->
    let rand_ind = ref (RemoteSocketMap.cardinal cncts |> Random.int) in
    let remote = ref (RemoteSocketMap.choose cncts |> fst) in
    let local = ref (RemoteSocketMap.find !remote cncts) in
    let _ = RemoteSocketMap.iter (fun r l ->
        (if !rand_ind = 0 then (remote := r; local := l));
        rand_ind := !rand_ind - 1
      ) cncts in
    sckt.last_operation <- Some (Send (!local, !remote));
    promise_send_msg !local !remote msg



let send_msg ?(block=true) sckt other_omq_id msg =
  (* the message will contain the id (mine) as the first frame *)
  let msg = Json.output (sckt.identity, msg) |> Js.to_string |> string_to_msg_t in
  match sckt.kind with
    REQ -> (
      match sckt.last_operation with
        Some (Send (_, _)) -> OMQ_Exception "Called send twice in a row on a REQ socket" |> Lwt.fail
      | _ -> _round_robin_send_msg ~block sckt msg
    )
  | REP -> (
      match sckt.last_operation with
        Some (Recv (remote, local)) -> (
          match _get_connected_to local |> RemoteSocketSet.mem remote with
            true -> promise_send_msg local remote msg
          | false -> Lwt.return () (*silently discard, as in docs *)
        )
      | Some (Send (_, _)) -> OMQ_Exception "Called send twice in a row on a REP socket" |> Lwt.fail
      | None -> OMQ_Exception "Called send before any recv on a REP socket" |> Lwt.fail
    )
  | DEALER -> (
      Lwt.return ()
    )
  | ROUTER -> (
      let connection = OmqSocketIdMap.find_opt other_omq_id sckt.routing_table in
      match connection with
      | Some (local, remote) ->
        sckt.last_operation <- Some (Send (local, remote));
        Pcl_lwt.promise_send_msg local remote msg
      (* does not exist anymore, discard the message silently, as in the OMQ doc *)
      | None -> Lwt.return ()
    )
