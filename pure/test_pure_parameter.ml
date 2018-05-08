(** [ Test parameter server ]  *)

module PS = Actor_pure_param

let schedule workers =
  let tasks = List.map (fun x ->
    let k, v = Random.int 100, Random.int 1000 in (x, [(k,v)])
  ) workers in tasks

let push _ vars =
  let updates = List.map (fun (k,v) ->
    Printf.fprintf Pervasives.stdout "working on %i\n" v; Pervasives.flush Pervasives.stdout;
    (k,v) ) vars in
  updates

let test_context () =
  PS.register_schedule schedule;
  PS.register_push push;
  PS.start Sys.argv.(1) Actor_pure_config.manager_addr;
  Printf.fprintf Pervasives.stdout "do some work at master node\n"; Pervasives.flush Pervasives.stdout

let _ = test_context ()
