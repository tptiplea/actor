(** [ Actor ]
    connect to Manager, represent a working node/actor.
*)

open Actor_pure_types

let manager = Actor_pure_config.manager_addr |> Pcl_bindings.string_to_remote_sckt_t
let addr = "tcp://127.0.0.1:" ^ (Pcl_bindings.pcl_util_rand_str 10) |> Pcl_bindings.string_to_local_sckt_t
let myid = "worker_" ^ (Pcl_bindings.pcl_util_rand_str 4)

let register req id u_addr m_addr =
  Owl_log.info "%s\n" ("register -> " ^ (m_addr |> Pcl_bindings.remote_sckt_t_to_string));
  let%lwt _ = Actor_pure_utils.send req User_Reg [|id; (u_addr |> Pcl_bindings.local_sckt_t_to_string)|] in
  let%lwt _ = Omq_socket.recv_msg req in
  Lwt.return ()

let heartbeat req id u_addr m_addr =
  Owl_log.info "%s\n" ("heartbeat -> " ^ (m_addr |> Pcl_bindings.remote_sckt_t_to_string));
  let%lwt _ = Actor_pure_utils.send req Heartbeat [|id; (u_addr |> Pcl_bindings.local_sckt_t_to_string)|] in
  let%lwt _ = Omq_socket.recv_msg req in
  Lwt.return ()

let start_app app args =
  Owl_log.info "%s\n" ("starting job: " ^ app);
  Array.iter (fun a -> Owl_log.debug "with arg: %s\n" a) args;
  Jsl_bindings.jsl_spawn_job_with_args app args

let run id u_addr m_addr =
  Owl_log.debug "Started Actor WORKER, trying to connect to signalling server (%s)" Actor_pure_config.signalling_server_addr;
  (* set up connection to manager *)
  let%lwt unique_id, _ztx = Omq_context.create Actor_pure_config.signalling_server_addr in
  Owl_log.debug "ACTOR WORKER: connected to signalling_server_addr, got unique id (%s)" unique_id;
  let req = Omq_context.create_req_socket _ztx in
  Owl_log.debug "ACTOR WORKER: trying to connect to remote master with addr (%s)" (m_addr |> Pcl_bindings.remote_sckt_t_to_string);
  let%lwt local =  Omq_socket.connect_to_remote req m_addr in
  Owl_log.debug "ACTOR WORKER: connected to manager, I am listening on (%s)" (local |> Pcl_bindings.local_sckt_t_to_string);
  register req myid u_addr m_addr;%lwt
  (* set up local service *)
  let rep = Omq_context.create_rep_socket _ztx in
  Owl_log.debug "ACTOR WORKER: About to bind addr (%s)" (u_addr |> Pcl_bindings.local_sckt_t_to_string);
  Omq_socket.bind_local rep u_addr;%lwt
  Owl_log.debug "ACTOR WORKER: Bound addrs";
  while%lwt true do
    Omq_socket.set_recv_timeoutms rep (300 * 1000);
    try%lwt
      let%lwt m_pack = Omq_socket.recv_msg rep in
      let m = of_msg m_pack in
      match m.typ with
      | Job_Create -> (
          let app = m.par.(1) in
          let args : string array = Omq_utils.json_parse m.par.(2) in
          Owl_log.info "%s\n" (app ^ " <- " ^ m.par.(0));
          Omq_socket.send_msg rep (Omq_utils.json_stringify OK |> Omq_socket.string_to_omq_msg_t);%lwt
          Lwt.return (start_app app args)
        )
      | _ -> Lwt.return ()
    with
    | Unix.Unix_error (_,_,_) -> heartbeat req id u_addr m_addr
    | Omq_types.OMQ_Exception s -> Lwt.return (Owl_log.error "%s\n" s)
    | _exn -> Lwt.return (Owl_log.error "unknown error\n")
  done;%lwt
  Omq_context.close_rep_socket _ztx rep;
  Omq_context.close_req_socket _ztx req;
  Omq_context.terminate _ztx;
  Lwt.return ()

let _ = run myid addr manager
