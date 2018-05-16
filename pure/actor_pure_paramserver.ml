(** [ Model Parallel ] Parameter server module  *)

open Actor_pure_types

module Internal (KeyValueTypeSpecifier : KeyValueTypeSig) = struct
  type key_t = KeyValueTypeSpecifier.key_t
  type value_t = KeyValueTypeSpecifier.value_t
  type vars_t = (key_t * value_t) list

  (* the global context: master, worker, etc. *)
  let _context = ref None
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

  let _get_context () =
    match !_context with
      None -> failwith "Paramserver is not initialised!!"
    | Some ctx -> ctx

  let update_steps t wid =
    let w = Omq_socket.omq_socket_id_t_to_string wid in
    let t' = Hashtbl.find (_get_context()).worker_step w in
    match t > t' with
    | true  -> Lwt.return (
        Hashtbl.replace (_get_context()).worker_busy w 0;
        Hashtbl.replace (_get_context()).worker_step w t;
        Hashtbl.add (_get_context()).step_worker t w )
    | false -> Lwt.return_unit

  let _get : key_t -> (value_t * int) = function k ->
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
    let bindings = StrMap.bindings (_get_context()).workers in
    let threads = List.map (fun (_k, v) -> Actor_pure_utils.send ~bar:(_get_context()).step v t s) bindings in
    let%lwt _ = Lwt.join threads in
    Lwt.return ((_get_context()).step)

  let terminate () =
    let%lwt _ = _broadcast_all Terminate [||] in
    Lwt_js.sleep 1. (** FIXME: change to BSP *)

  let service_loop () =
    Owl_log.debug "parameter server @ %s\n" ((_get_context()).myself_addr |> Pcl_bindings.local_sckt_t_to_string);
    (* unmarshal the schedule and pull functions *)
    let schedule = !_schedule in
    let pull = !_pull in
    let barrier = !_barrier in
    let stop = !_stop in
    (* loop to process messages *)
    try%lwt while%lwt not (
        let ctx_ref = ref (_get_context()) in
        let should_stop = stop ctx_ref in
        _context := Some !ctx_ref;
        should_stop
      ) do
        (* synchronisation barrier check *)
        let ctx_ref = ref (_get_context()) in
        let t, passed = barrier ctx_ref in
        !ctx_ref.step <- t;
        _context := Some !ctx_ref;
        (* schecule the passed at every message arrival *)
        let%lwt tasks = schedule passed in
        let task_threads =
          List.map (fun (worker, task) ->
              let w = StrMap.find worker (_get_context()).workers in
              let s = Omq_utils.json_stringify task in
              let t = Hashtbl.find (_get_context()).worker_step worker + 1 in
              let _ = Hashtbl.replace (_get_context()).worker_busy worker 1 in
              Actor_pure_utils.send ~bar:t w PS_Schedule [|s|]
            ) tasks
        in
        let%lwt _ = Lwt.join task_threads in
        if List.length tasks > 0 then
          Owl_log.debug "schedule t:%i -> %i workers\n" (_get_context()).step (List.length tasks);
        (** wait for another message arrival *)
        let%lwt i, m = Actor_pure_utils.recv_with_id (_get_context()).myself_sock in
        let t = m.bar in
        match m.typ with
        | PS_Get -> (
            Owl_log.debug "%s: ps_get\n" ((_get_context()).myself_addr |> Pcl_bindings.local_sckt_t_to_string);
            let k : key_t = Omq_utils.json_parse m.par.(0) in
            let v, t' = _get k in
            let s = to_msg t' OK [| Omq_utils.json_stringify v |] in
            Omq_socket.send_msg_with_id (_get_context()).myself_sock i s (* note, this was block:false, but router always false in OMQ so far*)
          )
        | PS_Set -> (
            Owl_log.debug "%s: ps_set\n" ((_get_context()).myself_addr |> Pcl_bindings.local_sckt_t_to_string);
            let k : key_t = Omq_utils.json_parse m.par.(0) in
            let v : value_t = Omq_utils.json_parse m.par.(1) in
            Lwt.return (_set k v t)
          )
        | PS_Push -> (
            Owl_log.debug "%s: ps_push\n" ((_get_context()).myself_addr |> Pcl_bindings.local_sckt_t_to_string);
            let updates_promises = Omq_utils.json_parse m.par.(0) |> pull in
            let updates_done = List.map
                (fun update_promise -> let%lwt k, v = update_promise in Lwt.return (_set k v t))
                updates_promises
            in
            let%lwt _ = Lwt.join updates_done in
            update_steps t i
          )
        | _ -> Lwt.return ( Owl_log.warn "unknown mssage to PS\n" )
      done with Failure e -> (
        Owl_log.warn "%s\n" e;
        terminate ();%lwt
        Lwt.return (Omq_context.close_router_socket (_get_context()).ztx (_get_context()).myself_sock) )

  let init m context =
    _context := Some context;
    (* contact allocated actors to assign jobs *)
    let addrs = Omq_utils.json_parse m.par.(0) in
    let sockets_promises =
      List.map (fun x ->
          let req = Omq_context.create_req_socket (_get_context()).ztx in
          let%lwt local = Omq_socket.connect_to_remote req (x |> Pcl_bindings.string_to_remote_sckt_t) in
          Owl_log.info "Connected to addrs (%s), listening on local (%s)\n" x (local |> Pcl_bindings.local_sckt_t_to_string);
          let app = Jsl_bindings.jsl_get_job_name () in (* TODO: if we get JS code, get this *)
          let arg = Omq_utils.json_stringify Jsl_bindings.jsl_get_sysargs in
          (Actor_pure_utils.send req Job_Create [|((_get_context()).myself_addr |> Pcl_bindings.local_sckt_t_to_string); app; arg|]);%lwt
          Lwt.return req
        ) addrs
    in
    let _close_sockets_threads = List.map
        (fun sp -> let%lwt s = sp in Lwt.return (Omq_context.close_req_socket (_get_context()).ztx s))
        sockets_promises in
    let%lwt _ = Lwt.join _close_sockets_threads in
    (* wait until all the allocated actors register *)
    while%lwt (StrMap.cardinal (_get_context()).workers) < (List.length addrs) do
      let%lwt _i, m = Actor_pure_utils.recv_with_id (_get_context()).myself_sock in
      let s = Omq_context.create_dealer_socket (_get_context()).ztx in
      Omq_socket.set_send_high_water_mark s Actor_pure_config.high_water_mark;
      let%lwt local = Omq_socket.connect_to_remote s (m.par.(0) |> Pcl_bindings.string_to_remote_sckt_t) in
      Owl_log.info "paramserv: Connected to addrs (%s), listening on local (%s)\n" m.par.(0) (local |> Pcl_bindings.local_sckt_t_to_string);
      (_get_context()).workers <- (StrMap.add m.par.(0) s (_get_context()).workers);
      Lwt.return ()
    done;%lwt
    (* initialise the step <--> work tables *)
    StrMap.iter (fun k _v ->
        Hashtbl.add (_get_context()).worker_busy k 0;
        Hashtbl.add (_get_context()).worker_step k 0;
        Hashtbl.add (_get_context()).step_worker 0 k;
      ) (_get_context()).workers;
    (* enter into master service loop *)
    service_loop ()
end
