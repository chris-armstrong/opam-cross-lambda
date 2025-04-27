let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run ~name:"fiber_test" @@ fun sw ->
  Eio.Fiber.fork ~sw (fun () ->
      Eio.Time.sleep (Eio.Stdenv.clock env) 5.0;
      Eio.traceln "Fiber 1 finished");
  Eio.Fiber.fork ~sw (fun () ->
      Eio.Time.sleep (Eio.Stdenv.clock env) 2.0;
      Eio.traceln "Fiber 2 finished")
