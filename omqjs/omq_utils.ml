open Omq_types

(* Resolve a promise, if it is still pending *)
let safe_resolve_promise resolver value =
  try Lwt.wakeup_later resolver value; true
  with Invalid_argument _ -> false

(* Reject a promise, if it is still pending *)
let safe_reject_promise resolver exc =
  try Lwt.wakeup_later_exn resolver exc; true
  with Invalid_argument _ -> false

(* Timeout a promise, if it is still pending *)
let add_mstimeout_to_promise timeout_ms resolver exc =
  let timeout_sec = timeout_ms / 1000 in
  let f = (fun () -> ignore (safe_reject_promise resolver exc)) in
  Lwt_timeout.create timeout_sec f |> Lwt_timeout.start

let make_exn_fail_callback ?(context="") resolver =
  fun reason ->
    let reason = Pcl_bindings.fail_reason_t_to_string reason in
    let explanation = context ^ "|| reason: " ^ reason in
    ignore (safe_reject_promise resolver (OMQ_Exception explanation))
