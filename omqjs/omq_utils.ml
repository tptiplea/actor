open Omq_types

let make_exn_fail_callback ?(context="") resolver =
  fun reason ->
    let reason = Pcl_bindings.fail_reason_t_to_string reason in
    let explanation = context ^ "|| reason: " ^ reason in
    Lwt.wakeup_later_exn resolver (OMQ_Exception explanation)
