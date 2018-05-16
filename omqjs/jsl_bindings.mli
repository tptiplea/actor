(**
   Get the current job name
*)
val jsl_get_job_name : unit -> string

(**
   Get the sys args, the very first one is the job name.
*)
val jsl_get_sysargs : unit -> string array

(**
   Spawn the job with this name, and give those arguments.
*)
val jsl_spawn_job_with_args : string -> string array -> unit
