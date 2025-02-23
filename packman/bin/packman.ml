let pp_arg fmt (arg, _) = match arg with
  | OpamTypes.CString x -> Format.fprintf fmt "\"%s\"" x
  | OpamTypes.CIdent x -> Format.fprintf fmt "<%s>" x

;;

let pp_build fmt (args, _) = Format.fprintf fmt "%a" (Format.pp_print_list ~pp_sep:(Format.pp_print_space) pp_arg) args 

;;

let main () =
  let file = OpamFile.make (OpamFilename.of_string "../../opam-repository/packages/yojson/yojson.2.2.2/opam") in
  
  let opam = file |> OpamFile.OPAM.read in
  let name = opam |> OpamFile.OPAM.name |> OpamPackage.Name.to_string in
let version = opam |> OpamFile.OPAM.version |> OpamPackage.Version.to_string in
  Format.printf "Name = %s\nVersion = %s\n" name version;

  let build = OpamFile.OPAM.build opam in
  Format.printf "Build\n%a" (Format.pp_print_list ~pp_sep:(fun fmt () -> Format.fprintf fmt "<newline>@\n") pp_build) build



let _ = main()
