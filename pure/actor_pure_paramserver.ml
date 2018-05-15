(** [ Model Parallel ] Parameter server module  *)

open Actor_pure_types

module Internal (KeyValueTypeSpecifier : KeyValueTypeSig) = struct
  type key_t = KeyValueTypeSpecifier.key_t
  type value_t = KeyValueTypeSpecifier.value_t
  type vars_t = (key_t * value_t) list

(* the global context: master, worker, etc. *)
let _context = ref (Actor_pure_utils.empty_param_context ())
let _param : (Obj.t, Obj.t * int) Hashtbl.t = Hashtbl.create 1_000_000

(* default schedule function *)
let _default_schedule : (string list -> (string * (key_t * value_t) list) list Lwt.t) = fun _ -> Lwt.return [ ] (** TODO: fix scheduler ... *)
let _schedule = ref ( _default_schedule )

let update_schedule_fun f = (_schedule := f)

(* default pull function *)
let _default_pull : ((key_t * value_t) list -> (key_t * value_t) Lwt.t list) = fun updates -> List.map (fun p -> Lwt.return p) updates
let _pull = ref (_default_pull)

let update_pull_fun f = (_pull := f)

(* default stopping function *)
let _default_stop : param_context ref -> bool = fun _ -> false
let _stop = ref (_default_stop)

let update_stop_fun f = (_stop := f)

(* default barrier function *)
let _default_barrier = Actor_pure_barrier.param_bsp
let _barrier = ref ( _default_barrier)

let update_barrier_fun f = (_barrier := f)

let update_steps t w =
  let t' = Hashtbl.find !_context.worker_step w in
  match t > t' with
  | true  -> (
    Hashtbl.replace !_context.worker_busy w 0;
    Hashtbl.replace !_context.worker_step w t;
    Hashtbl.add !_context.step_worker t w )
  | false -> ()

let _get (k : key_t) =
  let k' = Obj.repr k in
  let v, t = Hashtbl.find _param k' in
  Obj.obj v, t

let _set (k : key_t) (v : value_t) (t : int) =
  let k' = Obj.repr k in
  let v' = Obj.repr v in
  match Hashtbl.mem _param k' with
  | true  -> Hashtbl.replace _param k' (v',t)
  | false -> Hashtbl.add _param k' (v',t)

let _broadcast_all t s =
  let bindings = StrMap.bindings !_context.workers in
  let threads = List.map (fun (_k, v) -> Actor_pure_utils.send ~bar:!_context.step v t s) bindings in
  let%lwt _ = Lwt.join threads in
  Lwt.return (!_context.step)

let terminate () =
  let%lwt _ = _broadcast_all Terminate [||] in
  Lwt_unix.sleep 1. (** FIXME: change to BSP *)

let service_loop () =
  Owl_log.debug "parameter server @ %s\n" !_context.myself_addr;
  (* unmarshal the schedule and pull functions *)
  let schedule = !_schedule in
  let pull = !_pull in
  let barrier = !_barrier in
  let stop = !_stop in
  (* loop to process messages *)
  try%lwt while%lwt not (stop _context) do
    (* synchronisation barrier check *)
    let t, passed = barrier _context in !_context.step <- t;
    (* schecule the passed at every message arrival *)
    let%lwt tasks = schedule passed in
    let task_threads =
    List.map (fun (worker, task) ->
      let w = StrMap.find worker !_context.workers in
      let s = Marshal.to_string task [] in
      let t = Hashtbl.find !_context.worker_step worker + 1 in
      let _ = Hashtbl.replace !_context.worker_busy worker 1 in
      Actor_pure_utils.send ~bar:t w PS_Schedule [|s|]
    ) tasks
    in
    let%lwt _ = Lwt.join task_threads in
    if List.length tasks > 0 then
      Owl_log.debug "schedule t:%i -> %i workers\n" !_context.step (List.length tasks);
    (** wait for another message arrival *)
    let%lwt i, m = Actor_pure_utils.recv !_context.myself_sock in
    let t = m.bar in
    match m.typ with
    | PS_Get -> (
      Owl_log.debug "%s: ps_get\n" !_context.myself_addr;
      let k = Marshal.from_string m.par.(0) 0 in
      let v, t' = _get k in
      let s = to_msg t' OK [| Marshal.to_string v [] |] in
      Actor_pure_zmq_repl.send_all ~block:false !_context.myself_sock (i, s)
      )
    | PS_Set -> (
      Owl_log.debug "%s: ps_set\n" !_context.myself_addr;
      let k = Marshal.from_string m.par.(0) 0 in
      let v = Marshal.from_string m.par.(1) 0 in
      Lwt.return (_set k v t)
      )
    | PS_Push -> (
      Owl_log.debug "%s: ps_push\n" !_context.myself_addr;
      let updates_promises = Marshal.from_string m.par.(0) 0 |> pull in
      let updates_done = List.map (fun update_promise -> let%lwt k, v = update_promise in Lwt.return (_set k v t)) updates_promises in
      let%lwt _ = Lwt.join updates_done in
      Lwt.return (update_steps t i)
      )
    | _ -> Lwt.return ( Owl_log.warn "unknown mssage to PS\n" )
  done with Failure e -> (
    Owl_log.warn "%s\n" e;
    terminate ();%lwt
    Lwt.return (Actor_pure_zmq_repl.close !_context.myself_sock) )

let init m context =
  _context := context;
  (* contact allocated actors to assign jobs *)
  let addrs = Marshal.from_string m.par.(0) 0 in
  let sockets_promises =
  List.map (fun x ->
    let req = Actor_pure_zmq_repl.create !_context.ztx Actor_pure_zmq_repl.req in
    Actor_pure_zmq_repl.connect req x;%lwt
    let app = Filename.basename Sys.argv.(0) in (* TODO: if we get JS code, get this *)
    let arg = Marshal.to_string Sys.argv [] in
    (Actor_pure_utils.send req Job_Create [|!_context.myself_addr; app; arg|]);%lwt Lwt.return req
  ) addrs
  in
  let _close_sockets_threads = List.map (fun sp -> let%lwt s = sp in Lwt.return (Actor_pure_zmq_repl.close s)) sockets_promises in
  let%lwt _ = Lwt.join _close_sockets_threads in
  (* wait until all the allocated actors register *)
  while%lwt (StrMap.cardinal !_context.workers) < (List.length addrs) do
    let%lwt _i, m = Actor_pure_utils.recv !_context.myself_sock in
    let s = Actor_pure_zmq_repl.create !_context.ztx Actor_pure_zmq_repl.dealer in
    Actor_pure_zmq_repl.set_send_high_water_mark s Actor_pure_config.high_warter_mark;
    Actor_pure_zmq_repl.connect s m.par.(0);%lwt
    !_context.workers <- (StrMap.add m.par.(0) s !_context.workers);
    Lwt.return ()
  done;%lwt
  (* initialise the step <--> work tables *)
  StrMap.iter (fun k _v ->
    Hashtbl.add !_context.worker_busy k 0;
    Hashtbl.add !_context.worker_step k 0;
    Hashtbl.add !_context.step_worker 0 k;
  ) !_context.workers;
  (* enter into master service loop *)
  service_loop ()
end
