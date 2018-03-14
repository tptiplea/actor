(** [ Actor ]
  connect to Manager, represent a working node/actor.
*)

open Actor_types

let manager = Actor_config.manager_addr
let addr = "tcp://127.0.0.1:" ^ (string_of_int (Random.int 10000 + 50000))
let myid = "worker_" ^ (string_of_int (Random.int 9000 + 1000))
let _ztx = Actor_zmq_repl.context_create ()

let register req id u_addr m_addr =
  Actor_logger.info "%s" ("register -> " ^ m_addr);
  Actor_utils.send req User_Reg [|id; u_addr|];
  ignore (Actor_zmq_repl.recv req)

let heartbeat req id u_addr m_addr =
  Actor_logger.info "%s" ("heartbeat -> " ^ m_addr);
  Actor_utils.send req Heartbeat [|id; u_addr|];
  ignore (Actor_zmq_repl.recv req)

let start_app app arg =
  Actor_logger.info "%s" ("starting job " ^ app);
  match Unix.fork () with
  | 0 -> if Unix.fork () = 0 then Unix.execv app arg else exit 0
  | _p -> ignore(Unix.wait ())

let deploy_app _x = Actor_logger.error "%s" "error, cannot find app!"

let run id u_addr m_addr =
  (* set up connection to manager *)
  let req = Actor_zmq_repl.create _ztx Actor_zmq_repl.req in
  Actor_zmq_repl.connect req m_addr;
  register req myid u_addr m_addr;
  (* set up local service *)
  let rep = Actor_zmq_repl.create _ztx Actor_zmq_repl.rep in
  Actor_zmq_repl.bind rep u_addr;
  while true do
    Actor_zmq_repl.set_receive_timeout rep (300 * 1000);
    try let m = of_msg (Actor_zmq_repl.recv rep) in
      match m.typ with
      | Job_Create -> (
        let app = m.par.(1) in
        let arg = Marshal.from_string m.par.(2) 0 in
        Actor_logger.info "%s" (app ^ " <- " ^ m.par.(0));
        Actor_zmq_repl.send rep (Marshal.to_string OK []);
        match Sys.file_exists app with
        | true ->  start_app app arg
        | false -> deploy_app app
        )
      | _ -> ()
    with
      | Unix.Unix_error (_,_,_) -> heartbeat req id u_addr m_addr
      | ZMQ.ZMQ_exception (_,s) -> Actor_logger.error "%s" s
      | _exn -> Actor_logger.error "unknown error"
  done;
  Actor_zmq_repl.close rep;
  Actor_zmq_repl.close req;
  Actor_zmq_repl.context_terminate _ztx

let () = run myid addr manager
