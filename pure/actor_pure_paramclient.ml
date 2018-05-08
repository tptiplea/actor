(** [ Model Parallel ] Parameter client module  *)

open Actor_pure_types

(* the global context: master, worker, etc. *)
let _context = ref (Actor_pure_utils.empty_param_context ())

(* default push function *)
let _default_push = fun _worker_id _vars -> []
let _push = ref (Marshal.to_string _default_push [ Marshal.Closures ])

let _get k =
  let k' = Marshal.to_string k [] in
  Actor_pure_utils.send ~bar:!_context.step !_context.master_sock PS_Get [|k'|];
  let m = of_msg (Actor_pure_zmq_repl.recv ~block:true !_context.master_sock) in
  Marshal.from_string m.par.(0) 0, m.bar

let _set k v t =
  let k' = Marshal.to_string k [] in
  let v' = Marshal.to_string v [] in
  Actor_pure_utils.send ~bar:t !_context.master_sock PS_Set [|k'; v'|]

let update_param x t =
  (* update multiple kvs, more efficient than set *)
  let x' = Marshal.to_string x [] in
  Actor_pure_utils.send ~bar:t !_context.master_sock PS_Push [|x'|]

let service_loop () =
  Printf.fprintf Pervasives.stderr "parameter worker @ %s\n" !_context.myself_addr; Pervasives.flush Pervasives.stderr;
  (* unmarshal the push function *)
  let push : 'a -> ('b * 'c) list -> ('b * 'c) list = Marshal.from_string !_push 0 in
  (* loop to process messages *)
  try while true do
    let _i, m = Actor_pure_utils.recv !_context.myself_sock in
    let t = m.bar in
    match m.typ with
    | PS_Schedule -> (
      Printf.fprintf Pervasives.stderr "%s: ps_schedule\n" !_context.myself_addr; Pervasives.flush Pervasives.stderr;
      !_context.step <- (if t > !_context.step then t else !_context.step);
      let vars = Marshal.from_string m.par.(0) 0 in
      let updates = push !_context.myself_addr vars in
      update_param updates t
      )
    | Terminate -> (
      Printf.fprintf Pervasives.stderr "%s: terminate\n" !_context.myself_addr; Pervasives.flush Pervasives.stderr;
      Actor_pure_utils.send ~bar:t !_context.master_sock OK [||];
      Unix.sleep 1; (* FIXME: sleep ... *)
      failwith ("#" ^ !_context.job_id ^ " terminated")
      )
    | _ -> ( Printf.fprintf Pervasives.stderr "unknown mssage to PS\n"; Pervasives.flush Pervasives.stderr )
  done with Failure e -> (
    Printf.fprintf Pervasives.stderr "%s\n" e; Pervasives.flush Pervasives.stderr;
    Actor_pure_zmq_repl.close !_context.myself_sock;
    Pervasives.exit 0 )

let init m context =
  _context := context;
  !_context.master_addr <- m.par.(0);
  (* connect to job master *)
  let master = Actor_pure_zmq_repl.create !_context.ztx Actor_pure_zmq_repl.dealer in
  Actor_pure_zmq_repl.set_send_high_water_mark master Actor_pure_config.high_warter_mark;
  Actor_pure_zmq_repl.set_identity master !_context.myself_addr;
  Actor_pure_zmq_repl.connect master !_context.master_addr;
  Actor_pure_utils.send master OK [|!_context.myself_addr|];
  !_context.master_sock <- master;
  (* enter into worker service loop *)
  service_loop ()
