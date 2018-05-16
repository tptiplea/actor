(** [ Model Parallel ] Parameter client module  *)

open Actor_pure_types

module Internal (KeyValueTypeSpecifier : KeyValueTypeSig) = struct
  type key_t = KeyValueTypeSpecifier.key_t
  type value_t = KeyValueTypeSpecifier.value_t
  type vars_t = (key_t * value_t) list

  (* the global context: master, worker, etc. *)
  let _context = ref None
  let _get_context () =
    match !_context with
      None -> failwith "Paramclient is not initialised!!"
    | Some ctx -> ctx

  let _get : key_t -> (value_t * int) Lwt.t = function k ->
  match !_context with
    None -> failwith "Paramclient is not initialised!!"
  | Some ctx ->
    let k' = Omq_utils.json_stringify k in
    let%lwt _ = Actor_pure_utils.send ~bar:ctx.step ctx.master_sock PS_Get [|k'|] in
    let%lwt m = (Omq_socket.recv_msg ctx.master_sock) in
    let m = of_msg m in
    Lwt.return (Omq_utils.json_parse m.par.(0), m.bar)


  let _set (k : key_t) (v : value_t) (t : int) =
    match !_context with
      None -> failwith "Paramclient is not initialised!!"
    | Some ctx ->
      let k' = Omq_utils.json_stringify k in
      let v' = Omq_utils.json_stringify v in
      Actor_pure_utils.send ~bar:t ctx.master_sock PS_Set [|k'; v'|]


  (* default push function *)
  let _default_push : (string -> vars_t -> vars_t) = fun _worker_id _vars -> []
  let _push = ref _default_push

  let update_push_fun f = _push := f

  let update_param (x : vars_t) (t : int) =
    match !_context with
      None -> failwith "Paramclient is not initialised!!"
    | Some ctx ->
      (* update multiple kvs, more efficient than set *)
      let x' = Omq_utils.json_stringify x in
      Actor_pure_utils.send ~bar:t ctx.master_sock PS_Push [|x'|]

  let service_loop () =
    match !_context with
      None -> failwith "Paramclient is not initialised!!"
    | Some ctx ->
      Owl_log.debug "parameter worker @ %s\n" (ctx.myself_addr |> Pcl_bindings.local_sckt_t_to_string);
      (* unmarshal the push function *) (* note, marshalling removed *)
      let push : string -> vars_t -> vars_t = !_push in
      (* loop to process messages *)
      try%lwt while%lwt true do
          let%lwt _i, m = Actor_pure_utils.recv_with_id ctx.myself_sock in
          let t = m.bar in
          match m.typ with
          | PS_Schedule -> (
              Owl_log.debug "%s: ps_schedule\n" (ctx.myself_addr |> Pcl_bindings.local_sckt_t_to_string);
              ctx.step <- (if t > ctx.step then t else ctx.step);
              let vars : vars_t = Omq_utils.json_parse m.par.(0) in
              let updates = push (ctx.myself_addr |> Pcl_bindings.local_sckt_t_to_string) vars in
              update_param updates t
            )
          | Terminate -> (
              Owl_log.debug "%s: terminate\n" (ctx.myself_addr |> Pcl_bindings.local_sckt_t_to_string);
              Actor_pure_utils.send ~bar:t ctx.master_sock OK [||];%lwt
              Lwt_js.sleep 1.0;%lwt (* FIXME: sleep ... *)
              Lwt.return (failwith ("#" ^ ctx.job_id ^ " terminated"))
            )
          | _ -> Lwt.return ( Owl_log.debug "unknown mssage to PS\n" )
        done with Failure e -> (
          Owl_log.warn "%s\n" e;
          Omq_context.close_router_socket ctx.ztx ctx.myself_sock;
          Pervasives.exit 0 )

  let init m context =
    context.master_addr <- m.par.(0) |> Pcl_bindings.string_to_remote_sckt_t;
    (* connect to job master *)
    let master = Omq_context.create_dealer_socket context.ztx in
    Omq_socket.set_send_high_water_mark master Actor_pure_config.high_water_mark;
    Omq_socket.set_identity master (context.myself_addr |> Pcl_bindings.local_sckt_t_to_string |> Omq_socket.string_to_omq_socket_id_t);
    let%lwt local = Omq_socket.connect_to_remote master context.master_addr in
    Owl_log.info "Successfully connected to master with local address (%s)\n" (local |> Pcl_bindings.local_sckt_t_to_string);
    Actor_pure_utils.send master OK [|context.myself_addr |> Pcl_bindings.local_sckt_t_to_string|];%lwt
    context.master_sock <- master;
    _context := Some context;
    (* enter into worker service loop *)
    service_loop ()
end
