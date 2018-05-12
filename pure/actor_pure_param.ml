(** [ Model Parallel ] Parameter server module  *)

open Actor_pure_types

module Internal(KeyValueTypeSpecifier : KeyValueTypeSig) = struct
  type key_t = KeyValueTypeSpecifier.key_t
  type value_t = KeyValueTypeSpecifier.value_t
  type vars_t = (key_t * value_t) list

  module MyClient = Actor_pure_paramclient.Internal(KeyValueTypeSpecifier)
  module MyServer = Actor_pure_paramserver.Internal(KeyValueTypeSpecifier)

type param_context = Actor_pure_types.param_context
type barrier = ASP | BSP | SSP | PSP

let start ?barrier jid url =
  (* reset the barrier control if specifed *)
  let _barrier_str = match barrier with
    | Some ASP -> Actor_pure_barrier.param_asp
    | Some BSP -> Actor_pure_barrier.param_bsp
    | Some SSP -> Actor_pure_barrier.param_ssp
    | Some PSP -> failwith "Actor_pure_param:start:psp"
    | None     -> MyServer.(!_barrier)
  in
  MyServer.update_barrier_fun _barrier_str;
  (* start preparing communication context *)
  let _ztx = Actor_pure_zmq_repl.context_create () in
  let%lwt _addr, _router = Actor_pure_utils.bind_available_addr _ztx in
  let req = Actor_pure_zmq_repl.create _ztx Actor_pure_zmq_repl.req in
  Actor_pure_zmq_repl.connect req url;%lwt
  Actor_pure_utils.send req Job_Reg [|_addr; jid|];%lwt
  (* create and initialise part of the context *)
  let _context = Actor_pure_utils.empty_param_context () in
  _context.job_id <- jid;
  _context.myself_addr <- _addr;
  _context.myself_sock <- _router;
  _context.ztx <- _ztx;
  (* depends on the role, start server or client *)
  let%lwt m_pack = (Actor_pure_zmq_repl.recv req) in
  let m = of_msg m_pack in
  let%lwt _ = match m.typ with
    | Job_Master -> MyServer.init m _context
    | Job_Worker -> MyClient.init m _context
    | _ -> Lwt.return (Printf.fprintf Pervasives.stdout "%s\n" "unknown command"; Pervasives.flush Pervasives.stdout)
  in
  Lwt.return (Actor_pure_zmq_repl.close req)

let register_barrier (f) =
  MyServer.update_barrier_fun f

let register_schedule f =
  MyServer.update_schedule_fun f

let register_pull f =
  MyServer.update_pull_fun f

let register_push f =
  MyClient.update_push_fun f

let register_stop f =
  MyServer.update_stop_fun f

let get k =
  match MyServer.(!_context.job_id) = "" with
  | true  -> MyClient._get k
  | false -> Lwt.return (MyServer._get k)

let set k v =
  match MyServer.(!_context.job_id) = "" with
  | true  -> MyClient.(_set k v !_context.step)
  | false -> Lwt.return (MyServer.(_set k v !_context.step))

let keys () = Hashtbl.fold (fun k _v l -> l @ [ Obj.obj k ]) MyServer._param []

let worker_num () =
  match MyServer.(!_context.job_id) = "" with
  | true  -> failwith "Actor_pure_param:worker_num"
  | false -> StrMap.cardinal MyServer.(!_context.workers)

end
