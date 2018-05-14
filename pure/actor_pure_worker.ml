(** [ Actor ]
  connect to Manager, represent a working node/actor.
*)

open Actor_pure_types

let manager = Actor_pure_config.manager_addr
let addr = "tcp://127.0.0.1:" ^ (string_of_int (Random.int 10000 + 50000))
let myid = "worker_" ^ (string_of_int (Random.int 9000 + 1000))
let _ztx = Actor_pure_zmq_repl.context_create ()

let register req id u_addr m_addr =
  Owl_log.info "%s\n" ("register -> " ^ m_addr);
  let%lwt _ = Actor_pure_utils.send req User_Reg [|id; u_addr|] in
  let%lwt _ = Actor_pure_zmq_repl.recv req in
  Lwt.return ()

let heartbeat req id u_addr m_addr =
  Owl_log.info "%s\n" ("heartbeat -> " ^ m_addr);
  let%lwt _ = Actor_pure_utils.send req Heartbeat [|id; u_addr|] in
  let%lwt _ = Actor_pure_zmq_repl.recv req in
  Lwt.return ()

let start_app app arg =
  Owl_log.info "%s\n" ("starting job: " ^ app);
  match Lwt_unix.fork () with
  | 0 -> if Lwt_unix.fork () = 0 then Lwt.return (Unix.execv app arg) else Lwt.return (exit 0)
  | _p -> let%lwt _ = Lwt_unix.wait () in Lwt.return ()

let deploy_app _x = Lwt.return (Owl_log.error "%s\n" "error, cannot find app!")

let run id u_addr m_addr =
  (* set up connection to manager *)
  let req = Actor_pure_zmq_repl.create _ztx Actor_pure_zmq_repl.req in
  Actor_pure_zmq_repl.connect req m_addr;%lwt
  register req myid u_addr m_addr;%lwt
  (* set up local service *)
  let rep = Actor_pure_zmq_repl.create _ztx Actor_pure_zmq_repl.rep in
  Actor_pure_zmq_repl.bind rep u_addr;%lwt
  while%lwt true do
    Actor_pure_zmq_repl.set_receive_timeout rep (300 * 1000);
    try%lwt
     let%lwt m_pack = Actor_pure_zmq_repl.recv rep in
     let m = of_msg m_pack in
      match m.typ with
      | Job_Create -> (
        let app = m.par.(1) in
        let arg = Marshal.from_string m.par.(2) 0 in
        Owl_log.info "%s\n" (app ^ " <- " ^ m.par.(0));
        Actor_pure_zmq_repl.send rep (Marshal.to_string OK []);%lwt
        match Sys.file_exists app with
        | true ->  start_app app arg
        | false -> deploy_app app
        )
      | _ -> Lwt.return ()
    with
      | Unix.Unix_error (_,_,_) -> heartbeat req id u_addr m_addr
      | Zmq.ZMQ_exception (_,s) -> Lwt.return (Owl_log.error "%s\n" s)
      | _exn -> Lwt.return (Owl_log.error "unknown error\n")
  done;%lwt
  Actor_pure_zmq_repl.close rep;
  Actor_pure_zmq_repl.close req;
  Actor_pure_zmq_repl.context_terminate _ztx;
  Lwt.return ()

let () = Lwt_main.run (run myid addr manager)
