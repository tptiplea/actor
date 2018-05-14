module PCLB = Peer_comm_bindings
module PCConf = Peer_comm_config

let fail_callback = PCConf._test_general_fail_callback "CLIENT"

let test_server_addr = PCConf._test_server_addr |> PCLB.string_to_remote_sckt_t

let got_reply_from_server remote_sckt msg =
  let remote_sckt = PCLB.remote_sckt_t_to_string remote_sckt in
  let msg = PCLB.msg_t_to_string msg in
  print_string "CLIENT: Got the following message from Server:\n";
  print_string msg; print_string "\n";
  print_string "Is remote_socket equal to test_server_addr as expected? -- ";
  (if remote_sckt = PCConf._test_server_addr then "YES\n" else "NO\n") |> print_string;
  print_string "CLIENT is done! Everything went well I guess\n"

let sent_message_to_test_server local_scket () =
  "CLIENT: Sent message to TEST server!\n" |> print_string;
  PCLB.pcl_recv_msg
    local_scket
    got_reply_from_server
    (fail_callback "GETTING REPLY FROM SERVER")


let connected_to_test_server local_scket =
  let str_local_sckt = Peer_comm_bindings.local_sckt_t_to_string local_scket in
  "CLIENT: Connected to TEST Server with local socket " ^ str_local_sckt ^ "\n" |> print_string;
  PCLB.pcl_send_msg
    local_scket
    test_server_addr
    (PCLB.string_to_msg_t "Hi there SERVER, I am CLIENT 111!")
    (sent_message_to_test_server local_scket)
    (fail_callback "SENDING_MESSAGE_TO_TEST_SERVER")

let connected_to_signalling_server id =
  "CLIENT: connected to signalling server with id" ^ id ^ "!\n" |> print_string;
  PCLB.pcl_connect_to_address
    test_server_addr
    connected_to_test_server
    (fail_callback "CONNECT_TO_TEST_SERVER")


let _ =
  print_string "I am the CLIENT, trying to connect to server...\n";
  PCLB.pcl_start_comm_layer
    PCConf.signalling_server_url
    connected_to_signalling_server
    (fail_callback "START_PCL");
