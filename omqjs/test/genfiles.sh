cp ../../_build/default/omqjs/test_pcl_*.bc .
js_of_ocaml test_pcl_bindings_server.bc --pretty
js_of_ocaml test_pcl_bindings_client.bc --pretty
rm test_pcl_*.bc
