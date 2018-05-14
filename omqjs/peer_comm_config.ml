let signalling_server_url = "http://localhost:3000"

let _test_server_addr = ">_test_server_addr_<"

let _test_general_fail_callback who operation reason =
  print_string "\n\n-----------------\n";
  print_string ("Got an error on " ^ who ^ "'s side!:\n");
  print_string ("Was executing operation " ^ operation ^ "\n");
  Peer_comm_bindings.fail_reason_t_to_string reason |> print_string;
  print_string "\n\n-------------------";
  Pervasives.flush_all ()
