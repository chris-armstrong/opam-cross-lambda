let main () =
  let file = OpamFile.make (OpamFilename.of_string "../packages/ocaml-cross-x86_64-al2023/ocaml-cross-x86_64-al2023.5.3.0/opam") in
  let opam = OpamFile.OPAM.read file in
  let name = OpamFile.OPAM.name opam in
  (* let build = OpamFile.OPAM.build opam in *)
  Format.printf "Name = %s\n" (OpamPackage.Name.to_string name)


let _ = main()
