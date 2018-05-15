module PCLB = Pcl_bindings
module PCConf = Pcl_config

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

let was_request_sent = ref false
let my_local_addr = ref ""

let sent_message_to_test_server () =
  "CLIENT: Sent message to TEST server!\n" |> print_string;
  was_request_sent := true

let on_msg_callback remote local msg =
  if not !was_request_sent
  then print_string "\n\n!!!!!!!!!! CLIENT: ERROR. Got message before the request was sent to the server!!\n\n"
  else (
    if PCLB.local_sckt_t_to_string local
           <> PCLB.local_sckt_t_to_string local
    then
      print_string "\n\n!!!! CLIENT: ERROR. Message dest addr and local addr do not correspond!\n\n"
    else (
      if PCLB.remote_sckt_t_to_string remote
         <> PCLB.remote_sckt_t_to_string test_server_addr
      then
        print_string "\n\n!!!! CLIENT: ERROR. Message is not from server!!\n\n"
      else got_reply_from_server remote msg
    )
  )

let connected_to_test_server local_scket =
  let str_local_sckt = Pcl_bindings.local_sckt_t_to_string local_scket in
  "CLIENT: Connected to TEST Server with local socket " ^ str_local_sckt ^ "\n" |> print_string;
  PCLB.pcl_send_msg
    local_scket
    test_server_addr
    (PCLB.string_to_msg_t "Hi there SERVER, I am CLIENT 111!")
    sent_message_to_test_server
    (fail_callback "SENDING_MESSAGE_TO_TEST_SERVER")

let on_connection_to_callback local remote kind =
  "CLIENT: Got a new connection on local :" ^ (PCLB.local_sckt_t_to_string local) ^ "\n\n" |> print_string;
  (match kind with
    true -> "CLIENT: The remote " ^ (PCLB.remote_sckt_t_to_string remote) ^ " is connected\n\n" |> print_string
   |false -> "CLIENT: The remote " ^ (PCLB.remote_sckt_t_to_string remote) ^ " is DISCconnected\n\n" |> print_string);
  Pervasives.flush Pervasives.stdout

let connected_to_signalling_server id =
  "CLIENT: connected to signalling server with id" ^ id ^ "!\n" |> print_string;
  PCLB.pcl_connect_to_address
    test_server_addr
    on_msg_callback
    on_connection_to_callback
    connected_to_test_server
    (fail_callback "CONNECT_TO_TEST_SERVER")


let _ =
  print_string "I am the CLIENT, trying to connect to server...\n";
  PCLB.pcl_start_comm_layer
    PCConf.signalling_server_url
    connected_to_signalling_server
    (fail_callback "START_PCL");
