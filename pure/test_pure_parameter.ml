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
  let args = Jsl_bindings.jsl_get_sysargs () in
  let _ = Array.iter (fun a -> Owl_log.debug "test_pure_param: command line arg: %s" a) args in
  if (Array.length args < 2) then failwith "must provide job id!!";
  PS.start args.(1) Actor_pure_config.manager_addr;%lwt
  Lwt.return (Owl_log.info "do some work at master node\n")

let _ = test_context () (*
  let before = [|"test_pure_param"; "j0"|] in
  let _ = Owl_log.info "before len: %d" (Array.length before) in
  let _ = Array.iter (fun p -> Owl_log.info "before: %s" p) before in
  let str = Omq_utils.json_stringify before in
  let after : string array = Omq_utils.json_parse str in
  let _ = Owl_log.info "after len: %d" (Array.length after) in
  let _ = Array.iter (fun p -> Owl_log.info "after: %s" p) after in
  ()
           *)
