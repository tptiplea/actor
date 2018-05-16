(** [ Config ] contains the static configurations of the framework. *)

let _ = Owl_log.set_output Pervasives.stdout, Owl_log.set_level Owl_log.DEBUG
let _ = Owl_log.debug "logging set at debug lvl"

(** the signalling server address *)
let signalling_server_addr = "http://localhost:3000"

(** Manager's address, all workders connect to this address *)
let manager_addr = "tcp://127.0.0.1:5555"

(** Manager's identifier *)
let manager_id = "manager_0"

(** File system path, Irmin or HDFS *)
let dfs_path = "storage.data"

(** Log configs: path, level, color, etc. *)
(*
let level = Actor_logger.DEBUG
let logdir = "log/"
let _ =  Actor_logger.update_config level logdir ""
*)

(** Max queue length of ZMQ send and receive *)
let high_water_mark = 10_000

(** WebHDFS base addr and port *)
let webhdfs_addr = "192.168.99.100:50070"
