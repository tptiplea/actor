let my_addr = Pcl_bindings.string_to_local_sckt_t Pcl_config._test_server_addr

let _ =
  print_string ">>>TEST: I am the OMQ SERVER, trying to setup my listening REP OMQ Socket\n";
  let%lwt (unique_id, ctx) = Omq_context.create Pcl_config.signalling_server_url in
  Printf.printf ">>>TEST: Connected to signalling server, got context with id (%s)\n" unique_id;
  let sckt = Omq_context.create_socket ctx Omq_types.REP in
  let%lwt () = Omq_socket.bind_local sckt my_addr in
  Printf.printf ">>>TEST: Sucessfully bound addr, listening on %s\n" (Pcl_bindings.local_sckt_t_to_string my_addr);
  Printf.printf ">>>TEST: Waiting for request from client\n";
  let%lwt msg = Omq_socket.recv_msg sckt in
  let str_msg = Omq_socket.omq_msg_t_to_string msg in
  Printf.printf ">>>TEST: Sucessfully received message (%s) from a client!\n" str_msg;
  Printf.printf ">>>TEST: About to reply to client, in blocking mode!\n";
  let my_msg = "Hi there, client! This is your reply from OMQ Test Server!!" |> Omq_socket.string_to_omq_msg_t in
  let%lwt () = Omq_socket.send_msg ~block:true sckt my_msg in
  Printf.printf ">>>TEST: I am about to close down!\n";
  Omq_context.close_socket ctx sckt;
  Printf.printf ">>>TEST: Sucessfully closed socket! About to close context!\n";
  Omq_context.terminate ctx;
  Printf.printf ">>>TEST: ALL DONE!!!\n";
  Lwt.return ()
