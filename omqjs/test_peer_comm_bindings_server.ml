module PCLB = Peer_comm_bindings
module PCConf = Peer_comm_config

let fail_callback = PCConf._test_general_fail_callback "SERVER"

let my_addr = PCLB.string_to_local_sckt_t PCConf._test_server_addr

let sent_message_to_client () =
  print_string "SERVER: Sucessfully replied to client! I AM DONE!\n"

let got_message_from_client remote_socket msg =
  let str_remote_socket = PCLB.remote_sckt_t_to_string remote_socket in
  let msg = PCLB.msg_t_to_string msg in
  "SERVER: Got message: " ^ msg ^ "\n" |> print_string;
  "SERVER: From remote_socket: " ^ str_remote_socket ^ "\n" |> print_string;
  print_string "SERVER: Replying to client!";
  PCLB.pcl_send_msg
    my_addr
    remote_socket
    (PCLB.string_to_msg_t "Hey there CLIENT! I am server 222")
    sent_message_to_client
    (fail_callback "REPLYING TO CLIENT")

let bound_address () =
  print_string "SERVER: Sucessfully bound address, listening on it!\n";
  PCLB.pcl_recv_msg
    my_addr
    got_message_from_client
    (fail_callback "GETTING MESSAGE FROM CLIENT")

let connected_to_signalling_server id =
  ("CLIENT: connected to signalling server with id" ^ id ^ "!\n") |> print_string;
  PCLB.pcl_bind_address
    my_addr
    bound_address
    (fail_callback "BINDING ADDRESS")

let _ =
  print_string "I am the SERVER, trying to connect to server...\n";
  PCLB.pcl_start_comm_layer
    PCConf.signalling_server_url
    connected_to_signalling_server
    (fail_callback "START_PCL");
