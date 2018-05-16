let _jsl_jsapi_get_sysargs = Js.Unsafe.js_expr "pcl_jsapi_get_sysargs"
let _jsl_jsapi_get_job_name = Js.Unsafe.js_expr "pcl_jsapi_get_job_name"
let _jsl_jsapi_spawn_job_with_args = Js.Unsafe.js_expr "pcl_jsapi_spawn_job_with_args"

let _unsafe_wrap_string s = Js.string s |> Js.Unsafe.inject

let jsl_get_job_name () =
  let res = Js.Unsafe.fun_call _jsl_jsapi_get_job_name [||] in
  Js.to_string res

let jsl_get_sysargs () =
  let res = Js.Unsafe.fun_call _jsl_jsapi_get_sysargs [||] in
  let as_arr = Js.to_array res in
  Array.map (fun js_str -> Js.to_string js_str) as_arr

let jsl_spawn_job_with_args job_name args =
  let job_name = _unsafe_wrap_string job_name in
  let args = Array.map _unsafe_wrap_string args in
  let args = Js.Unsafe.inject args in
  let () = Js.Unsafe.fun_call _jsl_jsapi_spawn_job_with_args [|job_name; args|] in
  ()
