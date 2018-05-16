cp ../../../_build/default/omqjs/test_omq_*.bc .
js_of_ocaml test_omq_server.bc --pretty
js_of_ocaml test_omq_client.bc --pretty
#cp test_omq_client.js tmp_omq_client.js
#cp test_omq_server.js tmp_omq_server.js
#rm test_omq_server.js test_omq_client.js
#js-beautify tmp_omq_client.js > test_omq_client.js
#js-beautify tmp_omq_server.js > test_omq_server.js
rm test_omq_*.bc tmp_omq_*.js
