let _exists_singleton_context = ref false

type omq_context_t = {
  mutable rep_sockets : [`REP] Omq_socket.omq_socket_t list;
  mutable req_sockets : [`REQ] Omq_socket.omq_socket_t list;
  mutable dealer_sockets : [`DEALER] Omq_socket.omq_socket_t list;
  mutable router_sockets : [`ROUTER] Omq_socket.omq_socket_t list;
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
    Lwt.return (my_id, {rep_sockets = []; req_sockets = []; dealer_sockets = []; router_sockets = []; is_open = true})
  )

let _internal_register_req_socket ctx sckt =
  _ensure_is_open ctx;
  ctx.req_sockets <- sckt::ctx.req_sockets

let _internal_register_rep_socket ctx sckt =
  _ensure_is_open ctx;
  ctx.rep_sockets <- sckt::ctx.rep_sockets

let _internal_register_dealer_socket ctx sckt =
  _ensure_is_open ctx;
  ctx.dealer_sockets <- sckt::ctx.dealer_sockets

let _internal_register_router_socket ctx sckt =
  _ensure_is_open ctx;
  ctx.router_sockets <- sckt::ctx.router_sockets

let filter sckt = List.filter (fun s ->
    (Omq_socket.get_identity sckt |> Omq_socket.omq_socket_id_t_to_string) <>
    (Omq_socket.get_identity s |> Omq_socket.omq_socket_id_t_to_string)
  )

let _internal_deregister_req_socket ctx sckt =
  _ensure_is_open ctx;
  ctx.req_sockets <- filter sckt ctx.req_sockets

let _internal_deregister_rep_socket ctx sckt =
  _ensure_is_open ctx;
  ctx.rep_sockets <- filter sckt ctx.rep_sockets

let _internal_deregister_dealer_socket ctx sckt =
  _ensure_is_open ctx;
  ctx.dealer_sockets <- filter sckt ctx.dealer_sockets

let _internal_deregister_router_socket ctx sckt =
  _ensure_is_open ctx;
  ctx.router_sockets <- filter sckt ctx.router_sockets

let terminate ctx =
  _ensure_is_open ctx;
  (
    match ctx.req_sockets, ctx.rep_sockets, ctx.router_sockets, ctx.dealer_sockets with
    | [], [], [], [] -> print_string "INFO: Context is terminating correctly!\n"
    | _ ->
      print_string "ERROR: Context still has open sockets!! losing them!\n";
      let close_f = List.iter (fun sckt -> Omq_socket._internal_close sckt) in
      let _ = close_f ctx.req_sockets in
      let close_f = List.iter (fun sckt -> Omq_socket._internal_close sckt) in
      let _ = close_f ctx.req_sockets in
      let close_f = List.iter (fun sckt -> Omq_socket._internal_close sckt) in
      let _ = close_f ctx.dealer_sockets in
      let close_f = List.iter (fun sckt -> Omq_socket._internal_close sckt) in
      close_f ctx.router_sockets
  );
  ctx.is_open <- false

let create_rep_socket : omq_context_t -> [`REP] Omq_socket.omq_socket_t =
  function ctx ->
    let sckt = Omq_socket._internal_create_rep () in
    _internal_register_rep_socket ctx sckt;
    sckt

let create_req_socket : omq_context_t -> [`REQ] Omq_socket.omq_socket_t =
  function ctx ->
    let sckt = Omq_socket._internal_create_req () in
    _internal_register_req_socket ctx sckt;
    sckt

let create_dealer_socket : omq_context_t -> [`DEALER] Omq_socket.omq_socket_t =
  function ctx ->
    let sckt = Omq_socket._internal_create_dealer () in
    _internal_register_dealer_socket ctx sckt;
    sckt

let create_router_socket : omq_context_t -> [`ROUTER] Omq_socket.omq_socket_t =
  function ctx ->
    let sckt = Omq_socket._internal_create_router () in
    _internal_register_router_socket ctx sckt;
    sckt

let close_rep_socket ctx sckt =
  _internal_deregister_rep_socket ctx sckt;
  Omq_socket._internal_close sckt

let close_req_socket ctx sckt =
  _internal_deregister_req_socket ctx sckt;
  Omq_socket._internal_close sckt

let close_router_socket ctx sckt =
  _internal_deregister_router_socket ctx sckt;
  Omq_socket._internal_close sckt

let close_dealer_socket ctx sckt =
  _internal_deregister_dealer_socket ctx sckt;
  Omq_socket._internal_close sckt
