[@@@warning "-26"]
[@@@warning "-32"]

open Containers

let source_repository_path = Array.get Sys.argv 1
let destination_repository_path = Array.get Sys.argv 2
let package_name = Array.get Sys.argv 3
let package_version = Array.get Sys.argv 4
let cross_name = Array.get Sys.argv 5

let pp_arg fmt (arg, _) =
  match arg with
  | OpamTypes.CString x -> Format.fprintf fmt "\"%s\"" x
  | OpamTypes.CIdent x -> Format.fprintf fmt "<%s>" x

let pp_build fmt (args, _) =
  Format.fprintf fmt "%a"
    (Format.pp_print_list ~pp_sep:Format.pp_print_space pp_arg)
    args

let main () =
  let package_path =
    OpamFilename.Op.(
      OpamFilename.Dir.of_string source_repository_path
      / "packages" / package_name
      / (package_name ^ "." ^ package_version))
  in
  let file = OpamFile.make OpamFilename.Op.(package_path // "opam") in

  let opam = file |> OpamFile.OPAM.read in
  let name = opam |> OpamFile.OPAM.name |> OpamPackage.Name.to_string in
  let name = name ^ "-cross-" ^ cross_name |> OpamPackage.Name.of_string in
  let version =
    opam |> OpamFile.OPAM.version |> OpamPackage.Version.to_string
  in

  let depends =
    opam |> OpamFile.OPAM.depends
    |> OpamFormula.map (fun (name, fc) -> Atom (name, fc))
  in
  let opam =
    opam |> OpamFile.OPAM.with_depends depends |> OpamFile.OPAM.with_name name
  in
  let destination_package_path =
    OpamFilename.Op.(
      OpamFilename.Dir.of_string destination_repository_path
      / "packages"
      / (package_name ^ "-cross-" ^ cross_name)
      / (package_name ^ "-cross-" ^ cross_name ^ "." ^ package_version)
      // "opam")
  in
  let destination_file = OpamFile.make destination_package_path in
  OpamFile.OPAM.write destination_file opam
(* Format.printf "Name = %s\nVersion = %s\n" name version; *)
(**)
(* let build = OpamFile.OPAM.build opam in *)
(* Format.printf "Build\n%a" (Format.pp_print_list ~pp_sep:(fun fmt () -> Format.fprintf fmt "<newline>@\n") pp_build) build *)

let _ = main ()
