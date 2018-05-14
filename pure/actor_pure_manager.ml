(** [ Manager ]
  keeps running to manage a group of actors
*)

open Actor_pure_types

module Workers = struct
  let _workers = ref StrMap.empty

  let create id addr = {
    id = id;
    addr = addr;
    last_seen = Unix.time ()
  }

  let add id addr = _workers := StrMap.add id (create id addr) !_workers
  let remove id = _workers := StrMap.remove id !_workers
  let mem id = StrMap.mem id !_workers
  let to_list () = StrMap.fold (fun _k v l -> l @ [v]) !_workers []
  let addrs () = StrMap.fold (fun _k v l -> l @ [v.addr]) !_workers []
end

let addr = Actor_pure_config.manager_addr
let myid = Actor_pure_config.manager_id

let process r m =
  match m.typ with
  | User_Reg -> (
    let uid, addr = m.par.(0), m.par.(1) in
    if Workers.mem uid = false then
      Owl_log.info "%s\n" (uid ^ " @ " ^ addr);
      Workers.add uid addr;
      Actor_pure_utils.send r OK [||]
    )
  | Job_Reg -> (
    let master, jid = m.par.(0), m.par.(1) in
    if Actor_pure_service.mem jid = false then (
      Actor_pure_service.add jid master;
      (* FIXME: currently send back all nodes as workers *)
      let addrs = Marshal.to_string (Workers.addrs ()) [] in
      Actor_pure_utils.send r Job_Master [|addrs|] )
    else
      let master = (Actor_pure_service.find jid).master in
      Actor_pure_utils.send r Job_Worker [|master|]
    )
  | Heartbeat -> (
    Owl_log.info "%s\n" ("heartbeat @ " ^ m.par.(0));
    Workers.add m.par.(0) m.par.(1);
    Actor_pure_utils.send r OK [||]
    )
  | P2P_Reg -> (
    let addr, jid = m.par.(0), m.par.(1) in
    Owl_log.info "p2p @ %s job:%s\n" addr jid;
    if Actor_pure_service.mem jid = false then Actor_pure_service.add jid "";
    let peers = Actor_pure_service.choose_workers jid 10 in
    let peers = Marshal.to_string peers [] in
    Actor_pure_service.add_worker jid addr;
    Actor_pure_utils.send r OK [|peers|]
    )
  | _ -> Lwt.return (Owl_log.error "unknown message type\n")

let run _id addr =
  let _ztx = Actor_pure_zmq_repl.context_create () in
  let rep = Actor_pure_zmq_repl.create _ztx Actor_pure_zmq_repl.rep in
  Actor_pure_zmq_repl.bind rep addr;%lwt
  while%lwt true do
    let%lwt m_pack = (Actor_pure_zmq_repl.recv rep) in
    let m = of_msg m_pack in
    process rep m
  done;%lwt
  Actor_pure_zmq_repl.close rep;
  Actor_pure_zmq_repl.context_terminate _ztx;
  Lwt.return ()

let install_app _x = None

let _ = run myid addr
