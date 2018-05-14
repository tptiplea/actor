(* Opaque types to enforce the order of arguments *)
type msg_t = string
type local_sckt_t = string
type remote_sckt_t = string
type fail_reason_t = string

let _id x = x
let string_to_msg_t = _id
let msg_t_to_string = _id
let local_sckt_t_to_string = _id
let string_to_local_sckt_t = _id
let remote_sckt_t_to_string = _id
let string_to_remote_sckt_t = _id
let fail_reason_t_to_string = _id
let string_to_fail_reason_t = _id

(** A failure callback is given a stringified reason for the failure *)
type fail_callback_t = fail_reason_t -> unit

(* The javascript functions *)
let _pcl_jsapi_start_comm_layer_jsfun = Js.Unsafe.js_expr "pcl_jsapi_start_comm_layer"
let _pcl_jsapi_bind_address_jsfun = Js.Unsafe.js_expr "pcl_jsapi_bind_address"
let _pcl_jsapi_deallocate_address_jsfun = Js.Unsafe.js_expr "pcl_jsapi_deallocate_address"
let _pcl_jsapi_connect_to_address_jsfun = Js.Unsafe.js_expr "pcl_jsapi_connect_to_address"
let _pcl_jsapi_send_msg_jsfun = Js.Unsafe.js_expr "pcl_jsapi_send_msg"
let _pcl_jsapi_recv_msg_jsfun = Js.Unsafe.js_expr "pcl_jsapi_recv_msg"

let _unsafe_wrap_unit_arg_fun (f : unit -> 'a) =
  Js.wrap_callback f |> Js.Unsafe.inject

let _unsafe_wrap_string_arg_fun (f : string -> 'a) =
  let f_safe = (fun js_str -> f (Js.to_string js_str)) in
  Js.wrap_callback f_safe |> Js.Unsafe.inject

let _unsafe_wrap_2_string_args_fun (f : string -> string -> 'a) =
  let f_safe = (fun js_str1 js_str2
                 -> f (Js.to_string js_str1) (Js.to_string js_str2)) in
  Js.wrap_callback f_safe |> Js.Unsafe.inject

let _unsafe_wrap_string s = Js.string s |> Js.Unsafe.inject

let _is_comm_layer_started = ref false

let pcl_start_comm_layer = fun (server_url : string)
    (ok_callback : string -> unit) (fail_callback : fail_callback_t) ->
  let server_url = _unsafe_wrap_string server_url in
  let ok_callback = _unsafe_wrap_string_arg_fun ok_callback in
  let fail_callback = _unsafe_wrap_string_arg_fun fail_callback in
  Js.Unsafe.fun_call
    _pcl_jsapi_start_comm_layer_jsfun [|server_url; ok_callback; fail_callback|]

let pcl_bind_address (address : local_sckt_t)
    (ok_callback : unit -> unit) (fail_callback : fail_callback_t) =
  let address = _unsafe_wrap_string address in
  let ok_callback = _unsafe_wrap_unit_arg_fun ok_callback in
  let fail_callback = _unsafe_wrap_string_arg_fun fail_callback in
  Js.Unsafe.fun_call
    _pcl_jsapi_bind_address_jsfun [|address; ok_callback; fail_callback|]

let pcl_deallocate_address (address : local_sckt_t)
    (ok_callback : unit -> unit) (fail_callback : fail_callback_t) =
  let address = _unsafe_wrap_string address in
  let ok_callback = _unsafe_wrap_unit_arg_fun ok_callback in
  let fail_callback = _unsafe_wrap_string_arg_fun fail_callback in
  Js.Unsafe.fun_call
    _pcl_jsapi_deallocate_address_jsfun [|address; ok_callback; fail_callback|]

let pcl_connect_to_address (address : remote_sckt_t)
    (ok_callback : local_sckt_t -> unit) (fail_callback : fail_callback_t) =
  let address = _unsafe_wrap_string address in
  let ok_callback = _unsafe_wrap_string_arg_fun ok_callback in
  let fail_callback = _unsafe_wrap_string_arg_fun fail_callback in
  Js.Unsafe.fun_call
    _pcl_jsapi_connect_to_address_jsfun [|address; ok_callback; fail_callback|]

let pcl_send_msg (from_socket : local_sckt_t) (to_socket : remote_sckt_t)
    (msg : msg_t) (ok_callback : unit -> unit) (fail_callback : fail_callback_t) =
  let from_socket = _unsafe_wrap_string from_socket in
  let to_socket = _unsafe_wrap_string to_socket in
  let msg = _unsafe_wrap_string msg in
  let ok_callback = _unsafe_wrap_unit_arg_fun ok_callback in
  let fail_callback = _unsafe_wrap_string_arg_fun fail_callback in
  Js.Unsafe.fun_call
    _pcl_jsapi_send_msg_jsfun [|from_socket; to_socket; msg; ok_callback; fail_callback|]

let pcl_recv_msg (listen_on_socket : local_sckt_t) (timeout : int)
    (ok_callback : remote_sckt_t -> msg_t -> unit) (fail_callback : fail_callback_t) =
  let listen_on_socket = _unsafe_wrap_string listen_on_socket in
  let timeout = Js.Unsafe.inject timeout in
  let ok_callback = _unsafe_wrap_2_string_args_fun ok_callback in
  let fail_callback = _unsafe_wrap_string_arg_fun fail_callback in
  Js.Unsafe.fun_call
    _pcl_jsapi_recv_msg_jsfun [|listen_on_socket; timeout; ok_callback; fail_callback|]
