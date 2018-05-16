(** Some shared helper functions *)
open Actor_pure_types

(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
let recv_with_id sckt =
  let%lwt (id, msg) = Omq_socket.recv_msg_with_id sckt in
  Lwt.return (id, msg |> Actor_pure_types.of_msg)

(* Used in src/actor_manager *)
(* Used in src/actor_worker *)
(* Used in lib/actor_param *)
(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
let send ?(bar=0) sckt msg_typ par =
  try%lwt Omq_socket.send_msg ~block:false sckt (Actor_pure_types.to_msg bar msg_typ par)
  with _exn -> let hwm = Omq_socket.get_send_high_water_mark sckt in
  Owl_log.error "fail to send bar:%i hwm:%i\n" bar hwm;
  Lwt.return ()

let rec _bind_available_addr addr sock ztx =
  addr := "tcp://127.0.0.1:" ^ (Pcl_bindings.pcl_util_rand_str 10) |> Pcl_bindings.string_to_local_sckt_t;
  try%lwt Omq_socket.bind_local sock !addr
  with _exn -> _bind_available_addr addr sock ztx

(* Used in lib/actor_param *)
let bind_available_addr ztx =
  let router = Omq_context.create_router_socket ztx in
  let addr = ref ("" |> Pcl_bindings.string_to_local_sckt_t) in
  let%lwt _ = _bind_available_addr addr router ztx in
  Omq_socket.set_recv_high_water_mark router Actor_pure_config.high_water_mark;
  Lwt.return (!addr, router)

(* the following 3 functions are for shuffle operations *)

let _group_by_key x =
  let h = Hashtbl.create 1_024 in
  List.iter (fun (k,v) ->
    match Hashtbl.mem h k with
    | true  -> Hashtbl.replace h k ((Hashtbl.find h k) @ [v])
    | false -> Hashtbl.add h k [v]
  ) x;
  Hashtbl.fold (fun k v l -> (k,v) :: l) h []

let group_by_key x = (* FIXME: stack overflow if there too many values for a key *)
  let h, g = Hashtbl.(create 1_024, create 1_024) in
  List.iter (fun (k,v) -> Hashtbl.(add h k v; if not (mem g k) then add g k None)) x;
  Hashtbl.fold (fun k _ l -> (k,Hashtbl.find_all h k) :: l) g []

let flatten_kvg x =
  try List.map (fun (k,l) -> List.map (fun v -> (k,v)) l) x |> List.flatten
  with _exn -> print_endline "Error: flatten_kvg"; []

let choose_load x n i = List.filter (fun (k,_l) -> (Hashtbl.hash k mod n) = i) x

(* Used in lib/actor_param *)
(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
let create_param_context ztx job_id myself_addr myself_sock = {
    ztx         = ztx;
    job_id      = job_id;
    master_addr = "" |> Pcl_bindings.string_to_remote_sckt_t;
    myself_addr = myself_addr;
    master_sock = Omq_context.create_dealer_socket ztx;
    myself_sock = myself_sock;
    workers     = StrMap.empty;
    step        = 0;
    stale       = 1;
    worker_busy = Hashtbl.create 1_000;
    worker_step = Hashtbl.create 1_000;
    step_worker = Hashtbl.create 1_000;
  }
