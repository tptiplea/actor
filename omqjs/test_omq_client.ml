let test_server_addr = Pcl_bindings.string_to_remote_sckt_t Pcl_config._test_server_addr

let _ =
  print_string ">>>TEST: I am the OMQ CLIENT, trying to start the PCL\n";
  let%lwt (unique_id, ctx) = Omq_context.create Pcl_config.signalling_server_url in
  Printf.printf ">>>TEST: Connected to signalling server, got context with id (%s)\n" unique_id;
  Printf.printf ">>>TEST: Trying to create a REQ socket and connect to OMQ TEST SERVER\n";
  let sckt = Omq_context.create_req_socket ctx in
  let%lwt local = Omq_socket.connect_to_remote sckt test_server_addr in
  Printf.printf ">>>TEST: Sucessfully connected to OMQ Test Server listening on rand local (%s)\n" (Pcl_bindings.local_sckt_t_to_string local);
  Printf.printf ">>>TEST: About to send request to server\n";
  let raw_msg = "Hi there, Server! I am test client!!" |> Omq_socket.string_to_omq_msg_t in
  let%lwt () = Omq_socket.send_msg ~block:true sckt raw_msg in
  Printf.printf ">>>TEST: Sucessfully sent request to server\n";
  Printf.printf ">>>TEST: About to wait for reply\n";
  let%lwt msg = Omq_socket.recv_msg sckt in
  let str_msg = Omq_socket.omq_msg_t_to_string msg in
  Printf.printf ">>>TEST: Sucessfully received message (%s) from SERVER!\n" str_msg;
  Printf.printf ">>>TEST: I am about to close down!\n";
  Omq_context.close_req_socket ctx sckt;
  Printf.printf ">>>TEST: Sucessfully closed socket! About to close context!\n";
  Omq_context.terminate ctx;
  Printf.printf ">>>TEST: ALL DONE!!!\n";
  Lwt.return ()
