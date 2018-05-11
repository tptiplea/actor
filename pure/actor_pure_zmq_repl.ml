
(* Zmq Socket *)
(* has a type 'a t*)

(* Used in lib/actor_param *) (* through utils *)
type socket_router_t = [`Router] Zmq.Socket.t
type socket_dealer_t = [`Dealer] Zmq.Socket.t

(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
let dealer = Zmq.Socket.dealer
(* val dealer : [> `Dealer ] kind *)

(* Used in src/actor_worker *)
(* Used in lib/actor_param *)
(* Used in lib/actor_paramserver *)
let req = Zmq.Socket.req
(* val req : [> `Req ] kind *)

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
let rep = Zmq.Socket.rep
(* val rep : [> `Rep ] kind *)

(* Used in lib/actor_param *) (* through utils *)
let router = Zmq.Socket.router
(* val router : [> `Router ] kind *)

(* Used in lib/actor_paramclient *) (* through utils *)
(* Used in lib/actor_paramserver *) (* through utils *)
(* Always blocking *)
let recv_all s = Zmq.Socket.recv_all ~block:true s
(* val recv_all : ?block:bool -> 'a t -> string list *)
(* these are multipart messages *)

(* Used in src/actor_manager *) (* through utils *)
(* Used in src/actor_worker *) (* through utils *)
(* Used in lib/actor_param *) (* through utils *)
(* Used in lib/actor_paramclient *) (* through utils *)
(* Used in lib/actor_paramserver *) (* through utils *)
let send ?(block=true) v m = Zmq.Socket.send ~block v m
(* *)

(* Used in lib/actor_paramserver *)
let send_all ?(block=true) v m = Zmq.Socket.send_all ~block v m
(* val send : ?block:bool -> ?more:bool -> 'a t -> string -> unit *)

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
(* Used in lib/actor_param *)
(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
(* Used in lib/actor_param *) (* through utils *)
(* Used in lib/actor_param *) (* through utils *)
(* Used in lib/actor_paramclient *) (* through utils *)
(* Used in lib/actor_paramserver *) (* through utils *)
let create ztx req = Zmq.Socket.create ztx req
(*  val create : Zmq.Context.t -> 'a kind -> 'a t *)

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
let bind sock addr = Zmq.Socket.bind sock addr
(* val bind : 'a t -> string -> unit *)

(* Used in src/actor_worker *)
(* Used in lib/actor_param *)
(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
let connect req url = Zmq.Socket.connect req url
(* val connect : 'a t -> string -> unit *)

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
(* Used in lib/actor_param *)
(* Used in lib/actor_paramclient *)
(* Always blocking *)
let recv req = Zmq.Socket.recv ~block:true req
(* val recv : ?block:bool -> 'a t -> string *)

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
(* Used in lib/actor_param *)
(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
let close req = Zmq.Socket.close req
(* val close : 'a t -> unit *)

(* Used in lib/actor_paramclient *)
let set_identity sock addr = Zmq.Socket.set_identity sock addr
(* val set_identity : 'a t -> string -> unit *)

(* Used in lib/actor_paramclient *)
(* Used in lib/actor_paramserver *)
let set_send_high_water_mark s high_water_mark = Zmq.Socket.set_send_high_water_mark s high_water_mark
(* val set_send_high_water_mark : 'a t -> int -> unit *)

(* Used in src/actor_manager *) (* through utils *)
(* Used in src/actor_worker *) (* through utils *)
(* Used in lib/actor_param *) (* through utils *)
(* Used in lib/actor_paramclient *) (* through utils *)
(* Used in lib/actor_paramserver *) (* through utils *)
let get_send_high_water_mark s = Zmq.Socket.get_send_high_water_mark s
(* val get_send_high_water_mark : 'a t -> int *)

(* Used in lib/actor_param *) (* through utils *)
let set_receive_high_water_mark s high_water_mark = Zmq.Socket.set_receive_high_water_mark s high_water_mark
(* val set_receive_high_water_mark : 'a t -> int -> unit *)

(* Used in src/actor_worker *)
let set_receive_timeout sock timeout = Zmq.Socket.set_receive_timeout sock timeout
(* val set_receive_timeout : 'a t -> int -> unit *)

(* Zmq Context *)

type context_t = Zmq.Context.t
(* that type t *)

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
(* Used in lib/actor_param *) (* through utils *)
(* Used in lib/actor_paramclient *) (* through utils *)
(* Used in lib/actor_paramserver *) (* through utils *)
let context_create () = Zmq.Context.create ()
(* val create : unit -> t *)

(* Used in src/actor_worker *)
(* Used in src/actor_manager *)
(* Used in lib/actor_param *)
let context_terminate ztx = Zmq.Context.terminate ztx
(* val terminate : t -> unit *)
