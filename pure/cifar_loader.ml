let local_data_path () = failwith "uninmplemented"

(* load cifar train data, there are five batches in total. The loaded data is a
    10000 * 3072 matrix. Each row represents a 32 x 32 image of three colour
    channels, unravelled into a row vector. The labels are also returned. *)
let load_cifar_train_data : int -> (Owl_base_dense_ndarray_s.arr * Owl_base_dense_ndarray_s.arr * Owl_base_dense_ndarray_s.arr) =
  fun _ ->
    let bsize = 20 in
    (Owl_base_dense_ndarray.S.uniform [|bsize; 32; 32; 3|],
     Owl_base_dense_ndarray.S.uniform [|bsize; 1|],
     Owl_base_dense_ndarray.S.uniform [|bsize; 10|])

let load_cifar_test_data () = failwith "uninmplemented"


let load_mnist_train_data () = failwith "uninmplemented"

let load_mnist_test_data () = failwith "uninmplemented"
