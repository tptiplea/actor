(** [ Test parameter server ]  *)

module KeyValueTypeSpecifier = struct
  type key_t = int
  type value_t = int
end

module PS = Actor_pure_param.Internal(KeyValueTypeSpecifier)

let schedule workers =
  let tasks = List.map (fun x ->
      let k, v = Random.int 100, Random.int 1000 in (x, [(k,v)])
    ) workers in Lwt.return tasks

let push _ vars =
  let updates = List.map (fun (k,v) ->
      Owl_log.info "working on %i\n" v;
      (k,v) ) vars in
  updates

let test_context () =
  PS.register_schedule schedule;
  PS.register_push push;
  PS.start Sys.argv.(1) Actor_pure_config.manager_addr;%lwt
  Lwt.return (Owl_log.info "do some work at master node\n")

let _ = test_context ()
