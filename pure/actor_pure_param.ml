(** [ Model Parallel ] Parameter server module  *)

open Actor_pure_types

type param_context = Actor_pure_types.param_context
type barrier = ASP | BSP | SSP | PSP

let start ?barrier jid url =
  (* reset the barrier control if specifed *)
  let _barrier_str = match barrier with
    | Some ASP -> Marshal.to_string Actor_pure_barrier.param_asp [ Marshal.Closures ]
    | Some BSP -> Marshal.to_string Actor_pure_barrier.param_bsp [ Marshal.Closures ]
    | Some SSP -> Marshal.to_string Actor_pure_barrier.param_ssp [ Marshal.Closures ]
    | Some PSP -> failwith "Actor_pure_param:start:psp"
    | None     -> Actor_pure_paramserver.(!_barrier)
  in
  Actor_pure_paramserver._barrier := _barrier_str;
  (* start preparing communication context *)
  let _ztx = Actor_pure_zmq_repl.context_create () in
  let _addr, _router = Actor_pure_utils.bind_available_addr _ztx in
  let req = Actor_pure_zmq_repl.create _ztx Actor_pure_zmq_repl.req in
  Actor_pure_zmq_repl.connect req url;
  Actor_pure_utils.send req Job_Reg [|_addr; jid|];
  (* create and initialise part of the context *)
  let _context = Actor_pure_utils.empty_param_context () in
  _context.job_id <- jid;
  _context.myself_addr <- _addr;
  _context.myself_sock <- _router;
  _context.ztx <- _ztx;
  (* depends on the role, start server or client *)
  let m = of_msg (Actor_pure_zmq_repl.recv req) in
  let _ = match m.typ with
    | Job_Master -> Actor_pure_paramserver.init m _context
    | Job_Worker -> Actor_pure_paramclient.init m _context
    | _ -> Printf.fprintf Pervasives.stdout "%s\n" "unknown command"; Pervasives.flush Pervasives.stdout;
  in
  Actor_pure_zmq_repl.close req

let register_barrier (f : ps_barrier_typ) =
  Actor_pure_paramserver._barrier := Marshal.to_string f [ Marshal.Closures ]

let register_schedule (f : ('a, 'b, 'c) ps_schedule_typ) =
  Actor_pure_paramserver._schedule := Marshal.to_string f [ Marshal.Closures ]

let register_pull (f : ('a, 'b, 'c) ps_pull_typ) =
  Actor_pure_paramserver._pull := Marshal.to_string f [ Marshal.Closures ]

let register_push (f : ('a, 'b, 'c) ps_push_typ) =
  Actor_pure_paramclient._push := Marshal.to_string f [ Marshal.Closures ]

let register_stop (f : ps_stop_typ) =
  Actor_pure_paramserver._stop := Marshal.to_string f [ Marshal.Closures ]

let get k =
  match Actor_pure_paramserver.(!_context.job_id) = "" with
  | true  -> Actor_pure_paramclient._get k
  | false -> Actor_pure_paramserver._get k

let set k v =
  match Actor_pure_paramserver.(!_context.job_id) = "" with
  | true  -> Actor_pure_paramclient.(_set k v !_context.step)
  | false -> Actor_pure_paramserver.(_set k v !_context.step)

let keys () = Hashtbl.fold (fun k _v l -> l @ [ Obj.obj k ]) Actor_pure_paramserver._param []

let worker_num () =
  match Actor_pure_paramserver.(!_context.job_id) = "" with
  | true  -> failwith "Actor_pure_param:worker_num"
  | false -> StrMap.cardinal Actor_pure_paramserver.(!_context.workers)
