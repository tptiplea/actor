open Omq_types

let resolve_promise resolver value = Lwt.wakeup_later resolver value

(* Resolve a promise, if it is still pending *)
let safe_resolve_promise resolver value =
  try resolve_promise resolver value; true
  with Invalid_argument _ -> false

(* Reject a promise, if it is still pending *)
let safe_reject_promise resolver exc =
  try Lwt.wakeup_later_exn resolver exc; true
  with Invalid_argument _ -> false



let add_on_mstimeout_callback_to_promise_then_exc timeout_ms promise
    on_timeout_callback on_timeout_exc =
  let timeout_sec = (float_of_int timeout_ms) /. 1000. in
  let some_promise = Lwt.bind promise (fun res -> Lwt.return_some res) in
  let timeout = Lwt.bind (Lwt_js.sleep timeout_sec) (fun () -> Lwt.return_none) in
  match%lwt Lwt.choose [some_promise; timeout] with
    Some res -> Lwt.return res (* the result was first *)
  | None -> on_timeout_callback (); Lwt.fail on_timeout_exc

let make_exn_fail_callback ?(context="") resolver =
  fun reason ->
    let reason = Pcl_bindings.fail_reason_t_to_string reason in
    let explanation = context ^ "|| reason: " ^ reason in
    ignore (safe_reject_promise resolver (OMQ_Exception explanation))

let make_rand_local_addr len () =
  "random_addr_" ^ (Pcl_bindings.pcl_util_rand_str len) |> Pcl_bindings.string_to_local_sckt_t

(* NOTE: this is slow and inefficient, always copies *)
let queue_filter p q =
  let new_q = Queue.create () in
  Queue.iter (fun x -> if p x then Queue.push x new_q) q;
  new_q

let trim_queue_prefix p q =
  while (not (Queue.is_empty q)) && (p (Queue.peek q)) do
    ignore (Queue.pop q)
  done
