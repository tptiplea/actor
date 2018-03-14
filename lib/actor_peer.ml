(** [ Peer-to-Peer Parallel ]  *)

open Actor_types

let start jid url =
  let _ztx = Actor_zmq_repl.context_create () in
  let _addr, _router = Actor_utils.bind_available_addr _ztx in
  let req = Actor_zmq_repl.create _ztx Actor_zmq_repl.req in
  Actor_zmq_repl.connect req url;
  Actor_utils.send req P2P_Reg [|_addr; jid|];
  (* create and initialise part of the context *)
  let _context = Actor_utils.empty_peer_context () in
  _context.job_id <- jid;
  _context.myself_addr <- _addr;
  _context.myself_sock <- _router;
  _context.ztx <- _ztx;
  (* equivalent role, client is a new process *)
  let m = of_msg (Actor_zmq_repl.recv req) in
  let _ = match m.typ with
    | OK -> (
      match Unix.fork () with
      | 0 -> Actor_peerclient.init m _context
      | _p -> Actor_peerserver.init m _context
      )
    | _ -> Actor_logger.info "%s" "unknown command"
  in
  Actor_zmq_repl.close req

(* basic architectural functions for p2p parallel *)

let register_barrier (f : p2p_barrier_typ) =
  Actor_peerserver._barrier := Marshal.to_string f [ Marshal.Closures ]

let register_pull (f : ('a, 'b) p2p_pull_typ) =
  Actor_peerserver._pull := Marshal.to_string f [ Marshal.Closures ]

let register_schedule (f : 'a p2p_schedule_typ) =
  Actor_peerclient._schedule := Marshal.to_string f [ Marshal.Closures ]

let register_push (f : ('a, 'b) p2p_push_typ) =
  Actor_peerclient._push := Marshal.to_string f [ Marshal.Closures ]

let register_stop (f : p2p_stop_typ) =
  Actor_peerclient._stop := Marshal.to_string f [ Marshal.Closures ]

(* some helper functions for various strategies *)

let is_server () = Actor_peerclient.(!_context.job_id) = ""

let get k =
  match is_server () with
  | true  -> Actor_peerserver._get k
  | false -> Actor_peerclient._get k

let set k v =
  match is_server () with
  | true  -> Actor_peerserver.(_set k v !_context.step)
  | false -> Actor_peerclient.(_set k v)

let _swarm_size = None
