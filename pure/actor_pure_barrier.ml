(** [ Barrier module ]
  provides flexible synchronisation barrier controls.
*)

open Actor_pure_types

(* Param barrier: Bulk synchronous parallel *)
let param_bsp : Actor_pure_types.param_context ref -> int * string list = fun _context ->
  let num_finish = List.length (Hashtbl.find_all !_context.step_worker !_context.step) in
  let num_worker = StrMap.cardinal !_context.workers in
  match num_finish = num_worker with
  | true  -> !_context.step + 1, (StrMap.keys !_context.workers)
  | false -> !_context.step, []

(* Param barrier: Stale synchronous parallel *)
let param_ssp _context =
  let num_finish = List.length (Hashtbl.find_all !_context.step_worker !_context.step) in
  let num_worker = StrMap.cardinal !_context.workers in
  let t = match num_finish = num_worker with
    | true  -> !_context.step + 1
    | false -> !_context.step
  in
  let l = Hashtbl.fold (fun w t' l ->
    let busy = Hashtbl.find !_context.worker_busy w in
    match (busy = 0) && ((t' - t) < !_context.stale) with
    | true  -> l @ [ w ]
    | false -> l
  ) !_context.worker_step []
  in (t, l)

(* Param barrier: Asynchronous parallel *)
let param_asp _context = !_context.stale <- max_int; param_ssp _context
