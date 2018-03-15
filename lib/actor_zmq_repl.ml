
(* ZMQ Socket *)
(* Used in lib/actor_param *) (* through utils *)
type socket_router_t = [`Router] ZMQ.Socket.t
type socket_dealer_t = [`Dealer] ZMQ.Socket.t

(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
let dealer = ZMQ.Socket.dealer

(* Used in src/actor_worker *)
(* Used in lib/actor_param *)
(* Used in lib/actor_paramserver *)
let req = ZMQ.Socket.req

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
let rep = ZMQ.Socket.rep

(* Used in lib/actor_param *) (* through utils *)
let router = ZMQ.Socket.router

(* Used in lib/actor_paramclient *) (* through utils *)
(* Used in lib/actor_paramserver *) (* through utils *)
let recv_all ?(block=true) s = ZMQ.Socket.recv_all ~block s

(* Used in src/actor_manager *) (* through utils *)
(* Used in src/actor_worker *) (* through utils *)
(* Used in lib/actor_param *) (* through utils *)
(* Used in lib/actor_paramclient *) (* through utils *)
(* Used in lib/actor_paramserver *) (* through utils *)
let send ?(block=true) v m = ZMQ.Socket.send ~block v m

(* Used in lib/actor_paramserver *)
let send_all ?(block=true) v m = ZMQ.Socket.send_all ~block v m

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
(* Used in lib/actor_param *)
(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
(* Used in lib/actor_param *) (* through utils *)
(* Used in lib/actor_param *) (* through utils *)
(* Used in lib/actor_paramclient *) (* through utils *)
(* Used in lib/actor_paramserver *) (* through utils *)
let create ztx req = ZMQ.Socket.create ztx req

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
let bind sock addr = ZMQ.Socket.bind sock addr

(* Used in src/actor_worker *)
(* Used in lib/actor_param *)
(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
let connect req url = ZMQ.Socket.connect req url

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
(* Used in lib/actor_param *)
(* Used in lib/actor_paramclient *)
let recv ?(block=true) req = ZMQ.Socket.recv ~block req

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
(* Used in lib/actor_param *)
(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
let close req = ZMQ.Socket.close req

(* Used in lib/actor_paramclient *)
let set_identity sock addr = ZMQ.Socket.set_identity sock addr

(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
let set_send_high_water_mark s high_water_mark = ZMQ.Socket.set_send_high_water_mark s high_water_mark

(* Used in src/actor_manager *) (* through utils *)
(* Used in src/actor_worker *) (* through utils *)
(* Used in lib/actor_param *) (* through utils *)
(* Used in lib/actor_paramclient *) (* through utils *)
(* Used in lib/actor_paramserver *) (* through utils *)
let get_send_high_water_mark s = ZMQ.Socket.get_send_high_water_mark s

(* Used in lib/actor_param *) (* through utils *)
let set_receive_high_water_mark s high_water_mark = ZMQ.Socket.set_receive_high_water_mark s high_water_mark

(* Used in src/actor_worker *)
let set_receive_timeout sock timeout = ZMQ.Socket.set_receive_timeout sock timeout

(* ZMQ Context *)

type context_t = ZMQ.Context.t

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
(* Used in lib/actor_param *) (* through utils *)
(* Used in lib/actor_paramclient *) (* through utils *)
(* Used in lib/actor_paramserver *) (* through utils *)
let context_create () = ZMQ.Context.create ()

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
(* Used in lib/actor_param *)
let context_terminate ztx = ZMQ.Context.terminate ztx
