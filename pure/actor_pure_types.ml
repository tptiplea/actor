(** [ Types ]
  includes the types shared by different modules.
*)

module type KeyValueTypeSig = sig
  type key_t
  type value_t
end

module StrMap = struct
  include Map.Make (String)
  let keys x = List.map fst (bindings x)
  let values x = List.map snd (bindings x)
end

type color = Red | Green | Blue

type message_type =
  (* General messge types *)
  | OK | Fail | Heartbeat | User_Reg | Job_Reg | Job_Master | Job_Worker | Job_Create
  (* Data parallel: Mapre *)
  | MapTask | MapPartTask | FilterTask | ReduceByKeyTask | ShuffleTask | UnionTask
  | JoinTask | FlattenTask | ApplyTask | NopTask
  | Pipeline | Collect | Count | Broadcast | Fold | Reduce | Terminate | Load | Save
  (* Model Parallel: Param *)
  | PS_Get | PS_Set | PS_Schedule | PS_Push
  (* P2P Parallel: Peer *)
  | P2P_Reg | P2P_Connect | P2P_Ping | P2P_Join | P2P_Forward | P2P_Set | P2P_Get
  | P2P_Get_Q | P2P_Get_R | P2P_Copy | P2P_Push | P2P_Pull | P2P_Pull_Q | P2P_Pull_R
  | P2P_Bar

type message_rec = {
  mutable bar : int;
  mutable typ : message_type;
  mutable par : string array;
}

type param_context = {
          ztx         : Omq_context.omq_context_t;                    (* zmq context for communication *)
          job_id      : string;                           (* job id or swarm id, depends on paradigm *)
  mutable master_addr : Pcl_bindings.remote_sckt_t;                           (* different meaning in different paradigm *)
          myself_addr : Pcl_bindings.local_sckt_t;                           (* communication address of current process *)
  mutable master_sock : [`DEALER] Omq_socket.omq_socket_t;           (* socket of master_addr *)
          myself_sock : [`ROUTER] Omq_socket.omq_socket_t;           (* socket of myself_addr *)
  mutable workers     : [`DEALER] Omq_socket.omq_socket_t StrMap.t;  (* socket of workers or peers *)
  mutable step        : int;                              (* local step for barrier control *)
  mutable stale       : int;                              (* staleness variable for barrier control *)
  mutable worker_busy : (string, int) Hashtbl.t;          (* lookup table of a worker busy or not *)
  mutable worker_step : (string, int) Hashtbl.t;          (* lookup table of a worker's step *)
  mutable step_worker : (int, string) Hashtbl.t;          (* lookup table of workers at a specific step *)
}

type actor_rec = {
  id        : string;
  addr      : string;
  last_seen : float;
}

type data_rec = {
  id    : string;
  owner : string;
}

type service_rec = {
  id             : string;
  master         : string;
  mutable worker : string array;
}

(** two functions to translate between message rec and string *)

let to_msg b t p =
  let m = { bar = b; typ = t; par = p } in
  m |> Omq_utils.json_stringify |> Omq_socket.string_to_omq_msg_t

(* NOTE: Removed marshall from these two ,replaced with JSON *)
let of_msg msg =
  let m : message_rec = msg |> Omq_socket.omq_msg_t_to_string |> Omq_utils.json_parse in m;;

(* initialise some states *)

Random.self_init ();;
