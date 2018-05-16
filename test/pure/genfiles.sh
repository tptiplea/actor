cp ../../_build/default/pure/actor_pure_manager.bc .
cp ../../_build/default/pure/actor_pure_worker.bc .
cp ../../_build/default/pure/test_pure_parameter.bc .
js_of_ocaml actor_pure_manager.bc --pretty
js_of_ocaml actor_pure_worker.bc --pretty
js_of_ocaml test_pure_parameter.bc --pretty
#cp test_omq_client.js tmp_omq_client.js
#cp test_omq_server.js tmp_omq_server.js
#rm test_omq_server.js test_omq_client.js
#js-beautify tmp_omq_client.js > test_omq_client.js
#js-beautify tmp_omq_server.js > test_omq_server.js
rm actor_pure_worker.bc actor_pure_manager.bc test_pure_parameter.bc
