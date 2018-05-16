(* test parameter server engine *)
module M2 = Owl_baselwt_neural_parallel.Make (Owl_base_neural.S.Graph) (Actor_pure_param.Internal)
let test_neural_parallel () =
  let open Owl_base_neural.S in
  let open Graph in
  let nn =
    input [|32;32;3|]
    |> normalisation ~decay:0.9
    |> conv2d [|3;3;3;32|] [|1;1|] ~act_typ:Activation.Relu
    |> conv2d [|3;3;32;32|] [|1;1|] ~act_typ:Activation.Relu ~padding:VALID
    |> max_pool2d [|2;2|] [|2;2|] ~padding:VALID
    |> dropout 0.1
    |> conv2d [|3;3;32;64|] [|1;1|] ~act_typ:Activation.Relu
    |> conv2d [|3;3;64;64|] [|1;1|] ~act_typ:Activation.Relu ~padding:VALID
    |> max_pool2d [|2;2|] [|2;2|] ~padding:VALID
    |> dropout 0.1
    |> fully_connected 512 ~act_typ:Activation.Relu
    |> linear 10 ~act_typ:(Activation.Softmax 1)
    |> get_network
  in

  let x, _, y = Cifar_loader.load_cifar_train_data 1 in
  (*
  let params = Params.config
    ~batch:(Batch.Mini 100) ~learning_rate:(Learning_Rate.Adagrad 0.002) 0.05 in
  *)

  let params = Params.config
    ~batch:(Batch.Sample 100) ~learning_rate:(Learning_Rate.Adagrad 0.001)
    ~checkpoint:(Checkpoint.None) ~stopping:(Stopping.Const 1e-6) 10.
  in
  let url = Actor_pure_config.manager_addr in
  let jid = Sys.argv.(1) in
  M2.train ~params nn x y jid url

let _ = test_neural_parallel ()
