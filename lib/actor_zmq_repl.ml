
(* ZMQ Socket *)
type socket_router_t = [`Router] ZMQ.Socket.t
type socket_dealer_t = [`Dealer] ZMQ.Socket.t

let dealer = ZMQ.Socket.dealer

let req = ZMQ.Socket.req

let rep = ZMQ.Socket.rep

let router = ZMQ.Socket.router

let recv_all ?(block=true) s = ZMQ.Socket.recv_all ~block s

let send ?(block=true) v m = ZMQ.Socket.send ~block v m

let send_all ?(block=true) v m = ZMQ.Socket.send_all ~block v m

let create ztx req = ZMQ.Socket.create ztx req

let bind sock addr = ZMQ.Socket.bind sock addr

let connect req url = ZMQ.Socket.connect req url

let recv ?(block=true) req = ZMQ.Socket.recv ~block req

let close req = ZMQ.Socket.close req

let set_identity sock addr = ZMQ.Socket.set_identity sock addr

let set_send_high_water_mark s high_water_mark = ZMQ.Socket.set_send_high_water_mark s high_water_mark

let get_send_high_water_mark s = ZMQ.Socket.get_send_high_water_mark s

let set_receive_high_water_mark s high_water_mark = ZMQ.Socket.set_receive_high_water_mark s high_water_mark

let set_receive_timeout sock timeout = ZMQ.Socket.set_receive_timeout sock timeout

(* ZMQ Context *)

type context_t = ZMQ.Context.t

let context_create () = ZMQ.Context.create ()

let context_terminate ztx = ZMQ.Context.terminate ztx
