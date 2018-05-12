let local_data_path () =
  let d = Sys.getenv "HOME" ^ "/.owl/dataset/" in
  if Sys.file_exists d = false then (
    Owl_log.info "create %s" d;
    Unix.mkdir d 0o755;
  );
  d

(* load cifar train data, there are five batches in total. The loaded data is a
    10000 * 3072 matrix. Each row represents a 32 x 32 image of three colour
    channels, unravelled into a row vector. The labels are also returned. *)
let load_cifar_train_data : int -> (Owl_base_dense_ndarray_s.arr * Owl_base_dense_ndarray_s.arr * Owl_base_dense_ndarray_s.arr) =
fun batch ->
  let p = local_data_path () in
  Owl_io.marshal_from_file (p ^ "cifar10_train" ^ (string_of_int batch) ^ "_data"),
  Owl_io.marshal_from_file (p ^ "cifar10_train" ^ (string_of_int batch) ^ "_labels"),
  Owl_io.marshal_from_file (p ^ "cifar10_train" ^ (string_of_int batch) ^ "_lblvec")

let load_cifar_test_data () =
  let p = local_data_path () in
  Owl_io.marshal_from_file (p ^ "cifar10_test_data"),
  Owl_io.marshal_from_file (p ^ "cifar10_test_labels"),
  Owl_io.marshal_from_file (p ^ "cifar10_test_lblvec")


  let load_mnist_train_data () =
    let p = local_data_path () in
      Owl_io.marshal_from_file (p ^ "mnist-train-images"),
      Owl_io.marshal_from_file (p ^ "mnist-train-labels"),
      Owl_io.marshal_from_file (p ^ "mnist-train-lblvec")

  let load_mnist_test_data () =
    let p = local_data_path () in
      Owl_io.marshal_from_file (p ^ "mnist-test-images"),
      Owl_io.marshal_from_file (p ^ "mnist-test-labels"),
      Owl_io.marshal_from_file (p ^ "mnist-test-lblvec")
