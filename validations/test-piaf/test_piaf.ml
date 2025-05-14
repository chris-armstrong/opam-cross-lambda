let ( let* ) = Result.bind

let _ =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let open Piaf in
  let* response =
    Client.Oneshot.get ~sw env
      (Uri.of_string "https://jsonplaceholder.typicode.com/todos/1")
  in
  let* body = Body.to_string response.body in
  Printf.printf "Response: %s\n" body;
  Ok ()
