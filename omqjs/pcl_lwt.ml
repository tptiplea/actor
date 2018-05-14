let promise_start_comm_layer server_url =
  let promise, resolver = Lwt.task () in
  let ok_callback = (
    fun unique_id -> Lwt.wakeup_later resolver unique_id
  ) in
  let fail_callback =
    Omq_utils.make_exn_fail_callback
      ~context:("fail: start_comm_layer with server_url=" ^ server_url) resolver
  in
  Pcl_bindings.pcl_start_comm_layer server_url ok_callback fail_callback;
  promise

let promise_bind_address socket =
  let promise, resolver = Lwt.task () in
  let ok_callback = (fun () -> Lwt.wakeup_later resolver ()) in
  let fail_callback =
    Omq_utils.make_exn_fail_callback
      ~context:("fail: cannot bind " ^ (Pcl_bindings.local_sckt_t_to_string socket))
      resolver
  in
  Pcl_bindings.pcl_bind_address socket ok_callback fail_callback;
  promise

let promise_deallocate_address socket =
  let promise, resolver = Lwt.task () in
  let ok_callback = (fun () -> Lwt.wakeup_later resolver ()) in
  let fail_callback =
    Omq_utils.make_exn_fail_callback
      ~context:("fail: cannot deallocate " ^ (Pcl_bindings.local_sckt_t_to_string socket))
      resolver
  in
  Pcl_bindings.pcl_deallocate_address socket ok_callback fail_callback;
  promise


let promise_connect_to_address remote_socket =
  let promise, resolver = Lwt.task () in
  let ok_callback = (fun local_socket -> Lwt.wakeup_later resolver local_socket) in
  let fail_callback =
    Omq_utils.make_exn_fail_callback
      ~context:("fail: cannot connect to remote_socket " ^
                (Pcl_bindings.remote_sckt_t_to_string remote_socket))
      resolver
  in
  Pcl_bindings.pcl_connect_to_address remote_socket ok_callback fail_callback;
  promise

let promise_send_msg local remote msg =
  let promise, resolver = Lwt.task () in
  let ok_callback = (fun () -> Lwt.wakeup_later resolver ()) in
  let fail_callback =
    Omq_utils.make_exn_fail_callback
      ~context:("fail: cannot send msg to " ^
                (Pcl_bindings.remote_sckt_t_to_string remote))
      resolver
  in
  Pcl_bindings.pcl_send_msg local remote msg ok_callback fail_callback;
  promise

let promise_recv_msg local timeout =
  let promise, resolver = Lwt.task () in
  let ok_callback = (fun rem msg -> Lwt.wakeup_later resolver (rem, msg)) in
  let fail_callback =
    Omq_utils.make_exn_fail_callback
      ~context:("fail: cannot recv msg on " ^
                (Pcl_bindings.local_sckt_t_to_string local))
      resolver
  in
  Pcl_bindings.pcl_recv_msg local timeout ok_callback fail_callback;
  promise
