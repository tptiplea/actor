(** [ Service ]
  defines basic functionality of services
*)

open Actor_pure_types

let _services = ref StrMap.empty

let mem id = StrMap.mem id !_services

let add id master =
  let s = { id = id; master = master; worker = [||] } in
  _services := StrMap.add id s !_services

let add_worker id wid =
  let service = StrMap.find id !_services in
  let workers = Array.append service.worker [| wid |] in
  service.worker <- workers

let find id = StrMap.find id !_services


let _shuffle_ x =
  let l = Array.length x in
  let y = Array.copy x in
  begin
    for i = l - 1 downto 1 do
      let j = Random.int (i + 1) in
      let t = y.(j) in
      y.(j) <- y.(i);
      y.(i) <- t
    done;
    y
  end

let _n_choose_k_ x k =
  assert (Array.length x >= k);
  let shuff_x = _shuffle_ x in
  Array.init k (fun i -> shuff_x.(i))

let choose_workers id n =
  let s = StrMap.find id !_services in
  match Array.length s.worker > n with
  | true  -> _n_choose_k_ s.worker n
  | false -> s.worker
