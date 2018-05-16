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
    let%lwt (unique_id, _ztx) = Omq_context.create Actor_pure_config.signalling_server_addr in
    Owl_log.info "PARAM.ML: Successfully connected to signalling server with id (%s) and create OMQ Context" unique_id;
    let%lwt _addr, _router = Actor_pure_utils.bind_available_addr _ztx in
    let req = Omq_context.create_req_socket _ztx in
    let%lwt local = Omq_socket.connect_to_remote req (url |> Pcl_bindings.string_to_remote_sckt_t) in
    Owl_log.info "Successfully connected to remote (%s) with local address (%s)\n" url (local |> Pcl_bindings.local_sckt_t_to_string);
    Actor_pure_utils.send req Job_Reg [|_addr |> Pcl_bindings.local_sckt_t_to_string; jid|];%lwt
    (* create and initialise part of the context *)
    let _context = Actor_pure_utils.create_param_context _ztx jid _addr _router in
    (* depends on the role, start server or client *)
    let%lwt m_pack = (Omq_socket.recv_msg req) in
    let m = of_msg m_pack in
    let%lwt _ = match m.typ with
      | Job_Master -> MyServer.init m _context
      | Job_Worker -> MyClient.init m _context
      | _ -> Lwt.return (Owl_log.info "%s\n" "unknown command")
    in
    Lwt.return (Omq_context.close_req_socket _context.ztx req)

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
    match (MyServer._get_context()).job_id = "" with
    | true  -> MyClient._get k
    | false -> Lwt.return (MyServer._get k)

  let set k v =
    match (MyServer._get_context()).job_id = "" with
    | true  -> MyClient.(_set k v (_get_context()).step)
    | false -> Lwt.return (MyServer.(_set k v (_get_context()).step))

  let keys () = Hashtbl.fold (fun k _v l -> l @ [ Obj.obj k ]) MyServer._param []

  let worker_num () =
    match MyServer.((_get_context()).job_id) = "" with
    | true  -> failwith "Actor_pure_param:worker_num"
    | false -> StrMap.cardinal MyServer.((_get_context()).workers)

end
