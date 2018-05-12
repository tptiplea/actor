(** [ Model Parallel ] Parameter client module  *)

open Actor_pure_types

module Internal (KeyValueTypeSpecifier : KeyValueTypeSig) = struct
  type key_t = KeyValueTypeSpecifier.key_t
  type value_t = KeyValueTypeSpecifier.value_t
  type vars_t = (key_t * value_t) list

  (* the global context: master, worker, etc. *)
  let _context = ref (Actor_pure_utils.empty_param_context ())

  let _get (k : key_t) =
    let k' = Marshal.to_string k [] in
    let%lwt _ = Actor_pure_utils.send ~bar:!_context.step !_context.master_sock PS_Get [|k'|] in
    let%lwt m = (Actor_pure_zmq_repl.recv !_context.master_sock) in
    let m = of_msg m in
    Lwt.return (Marshal.from_string m.par.(0) 0, m.bar)


  let _set (k : key_t) (v : value_t) (t : int) =
    let k' = Marshal.to_string k [] in
    let v' = Marshal.to_string v [] in
    Actor_pure_utils.send ~bar:t !_context.master_sock PS_Set [|k'; v'|]


  (* default push function *)
  let _default_push : (string -> vars_t -> vars_t) = fun _worker_id _vars -> []
  let _push = ref _default_push

  let update_push_fun f = _push := f

  let update_param (x : vars_t) (t : int) =
    (* update multiple kvs, more efficient than set *)
    let x' = Marshal.to_string x [] in
    Actor_pure_utils.send ~bar:t !_context.master_sock PS_Push [|x'|]

  let service_loop () =
    Printf.fprintf Pervasives.stderr "parameter worker @ %s\n" !_context.myself_addr; Pervasives.flush Pervasives.stderr;
    (* unmarshal the push function *)
    let push : string -> vars_t -> vars_t = !_push in
    (* loop to process messages *)
    try%lwt while%lwt true do
      let%lwt _i, m = Actor_pure_utils.recv !_context.myself_sock in
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
          Actor_pure_utils.send ~bar:t !_context.master_sock OK [||];%lwt
          Lwt_unix.sleep 1.0;%lwt (* FIXME: sleep ... *)
          Lwt.return (failwith ("#" ^ !_context.job_id ^ " terminated"))
          )
        | _ -> Lwt.return ( Printf.fprintf Pervasives.stderr "unknown mssage to PS\n"; Pervasives.flush Pervasives.stderr )
    done with Failure e -> Lwt.return (
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
    Actor_pure_zmq_repl.connect master !_context.master_addr;%lwt
    Actor_pure_utils.send master OK [|!_context.myself_addr|];%lwt
    !_context.master_sock <- master;
    (* enter into worker service loop *)
    service_loop ()
end
