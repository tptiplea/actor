cp ../../_build/default/omqjs/test_peer_*.bc .
js_of_ocaml test_peer_comm_bindings_server.bc --pretty
js_of_ocaml test_peer_comm_bindings_client.bc --pretty
rm test_peer_*.bc
