exception OMQ_Exception of string

type omq_sckt_kind = [`REP | `REQ | `DEALER | `ROUTER]

let omq_sckt_kind_to_string = function
    `REP -> "REP"
  | `REQ ->  "REQ"
  | `DEALER -> "DEALER"
  | `ROUTER -> "ROUTER"
