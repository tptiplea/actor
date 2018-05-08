(** [ Model Parallel ] Parameter server module  *)

open Actor_pure_types

(* the global context: master, worker, etc. *)
let _context = ref (Actor_pure_utils.empty_param_context ())
let _param : (Obj.t, Obj.t * int) Hashtbl.t = Hashtbl.create 1_000_000

(* default schedule function *)
let _default_schedule = fun _ -> [ ] (** TODO: fix scheduler ... *)
let _schedule = ref (Marshal.to_string _default_schedule [ Marshal.Closures ])

(* default pull function *)
let _default_pull = fun updates -> updates
let _pull = ref (Marshal.to_string _default_pull [ Marshal.Closures ])

(* default stopping function *)
let _default_stop = fun _ -> false
let _stop = ref (Marshal.to_string _default_stop [ Marshal.Closures ])

(* default barrier function *)
let _default_barrier = Actor_pure_barrier.param_bsp
let _barrier = ref (Marshal.to_string _default_barrier [ Marshal.Closures ])

let update_steps t w =
  let t' = Hashtbl.find !_context.worker_step w in
  match t > t' with
  | true  -> (
    Hashtbl.replace !_context.worker_busy w 0;
    Hashtbl.replace !_context.worker_step w t;
    Hashtbl.add !_context.step_worker t w )
  | false -> ()

let _get k =
  let k' = Obj.repr k in
  let v, t = Hashtbl.find _param k' in
  Obj.obj v, t

let _set k v t =
  let k' = Obj.repr k in
  let v' = Obj.repr v in
  match Hashtbl.mem _param k' with
  | true  -> Hashtbl.replace _param k' (v',t)
  | false -> Hashtbl.add _param k' (v',t)

let _broadcast_all t s =
  StrMap.iter (fun _k v -> Actor_pure_utils.send ~bar:!_context.step v t s) !_context.workers;
  !_context.step

let terminate () =
  let _ = _broadcast_all Terminate [||] in
  Unix.sleep 1 (** FIXME: change to BSP *)

let service_loop () =
  Printf.fprintf Pervasives.stderr "parameter server @ %s\n" !_context.myself_addr;  Pervasives.flush Pervasives.stderr;
  (* unmarshal the schedule and pull functions *)
  let schedule : ('a, 'b, 'c) ps_schedule_typ = Marshal.from_string !_schedule 0 in
  let pull : ('a, 'b, 'c) ps_pull_typ = Marshal.from_string !_pull 0 in
  let barrier : ps_barrier_typ = Marshal.from_string !_barrier 0 in
  let stop : ps_stop_typ = Marshal.from_string !_stop 0 in
  (* loop to process messages *)
  try while not (stop _context) do
    (* synchronisation barrier check *)
    let t, passed = barrier _context in !_context.step <- t;
    (* schecule the passed at every message arrival *)
    let tasks = schedule passed in
    List.iter (fun (worker, task) ->
      let w = StrMap.find worker !_context.workers in
      let s = Marshal.to_string task [] in
      let t = Hashtbl.find !_context.worker_step worker + 1 in
      let _ = Hashtbl.replace !_context.worker_busy worker 1 in
      Actor_pure_utils.send ~bar:t w PS_Schedule [|s|]
    ) tasks;
    if List.length tasks > 0 then
      Printf.fprintf Pervasives.stderr "schedule t:%i -> %i workers\n" !_context.step (List.length tasks); Pervasives.flush Pervasives.stderr;
    (** wait for another message arrival *)
    let i, m = Actor_pure_utils.recv !_context.myself_sock in
    let t = m.bar in
    match m.typ with
    | PS_Get -> (
      Printf.fprintf Pervasives.stderr "%s: ps_get\n" !_context.myself_addr; Pervasives.flush Pervasives.stderr;
      let k = Marshal.from_string m.par.(0) 0 in
      let v, t' = _get k in
      let s = to_msg t' OK [| Marshal.to_string v [] |] in
      Actor_pure_zmq_repl.send_all ~block:false !_context.myself_sock [i;s]
      )
    | PS_Set -> (
      Printf.fprintf Pervasives.stderr "%s: ps_set\n" !_context.myself_addr; Pervasives.flush Pervasives.stderr;
      let k = Marshal.from_string m.par.(0) 0 in
      let v = Marshal.from_string m.par.(1) 0 in
      _set k v t
      )
    | PS_Push -> (
      Printf.fprintf Pervasives.stderr "%s: ps_push\n" !_context.myself_addr; Pervasives.flush Pervasives.stderr;
      let updates = Marshal.from_string m.par.(0) 0 |> pull in
      List.iter (fun (k,v) -> _set k v t) updates;
      update_steps t i
      )
    | _ -> ( Printf.fprintf Pervasives.stderr "unknown mssage to PS\n"; Pervasives.flush Pervasives.stderr )
  done with Failure e -> (
    Printf.fprintf Pervasives.stderr "%s\n" e; Pervasives.flush Pervasives.stderr;
    terminate ();
    Actor_pure_zmq_repl.close !_context.myself_sock )

let init m context =
  _context := context;
  (* contact allocated actors to assign jobs *)
  let addrs = Marshal.from_string m.par.(0) 0 in
  List.map (fun x ->
    let req = Actor_pure_zmq_repl.create !_context.ztx Actor_pure_zmq_repl.req in
    Actor_pure_zmq_repl.connect req x;
    let app = Filename.basename Sys.argv.(0) in
    let arg = Marshal.to_string Sys.argv [] in
    Actor_pure_utils.send req Job_Create [|!_context.myself_addr; app; arg|]; req
  ) addrs
  |> List.iter Actor_pure_zmq_repl.close;
  (* wait until all the allocated actors register *)
  while (StrMap.cardinal !_context.workers) < (List.length addrs) do
    let _i, m = Actor_pure_utils.recv !_context.myself_sock in
    let s = Actor_pure_zmq_repl.create !_context.ztx Actor_pure_zmq_repl.dealer in
    Actor_pure_zmq_repl.set_send_high_water_mark s Actor_pure_config.high_warter_mark;
    Actor_pure_zmq_repl.connect s m.par.(0);
    !_context.workers <- (StrMap.add m.par.(0) s !_context.workers);
  done;
  (* initialise the step <--> work tables *)
  StrMap.iter (fun k _v ->
    Hashtbl.add !_context.worker_busy k 0;
    Hashtbl.add !_context.worker_step k 0;
    Hashtbl.add !_context.step_worker 0 k;
  ) !_context.workers;
  (* enter into master service loop *)
  service_loop ()
