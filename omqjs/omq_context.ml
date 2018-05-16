let _exists_singleton_context = ref false

type omq_context_t = {
  mutable sockets : Omq_socket.omq_socket_t list;
  mutable is_open : bool;
}

let _ensure_is_open ctx =
  if not ctx.is_open
  then raise (Omq_types.OMQ_Exception "ERROR: Operation on closed context")

let create signalling_server_url =
  if (!_exists_singleton_context)
  then (
    let err_msg = "ERROR: There already is a request to create a context!!" in
    Printf.printf "%s\n" err_msg;
    raise (Omq_types.OMQ_Exception err_msg)
  ) else (
    _exists_singleton_context := true;
    let%lwt my_id = Pcl_lwt.promise_start_comm_layer signalling_server_url in
    Lwt.return (my_id, {sockets = []; is_open = true})
  )

let _internal_register_socket ctx sckt =
  _ensure_is_open ctx;
  ctx.sockets <- sckt::ctx.sockets

let _internal_deregister_socket ctx sckt =
  _ensure_is_open ctx;
  ctx.sockets <- List.filter (fun s ->
      (Omq_socket.get_identity sckt |> Omq_socket.omq_socket_id_t_to_string) <>
      (Omq_socket.get_identity s |> Omq_socket.omq_socket_id_t_to_string)
    ) ctx.sockets

let terminate ctx =
  _ensure_is_open ctx;
  (
    match ctx.sockets with
    | [] -> print_string "INFO: Context is terminating correctly!\n"
    | _ ->
      print_string "ERROR: Context still has open sockets!! losing them!\n";
      let copy = ctx.sockets in
      List.iter (fun sckt -> Omq_socket._internal_close sckt) copy
  );
  ctx.is_open <- false

let create_socket ctx k =
  let sckt = Omq_socket._internal_create k in
  _internal_register_socket ctx sckt;
  sckt

let close_socket ctx sckt =
  _internal_deregister_socket ctx sckt;
  Omq_socket._internal_close sckt
