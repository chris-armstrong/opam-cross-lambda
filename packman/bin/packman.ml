[@@@warning "-26"]
[@@@warning "-27"]
[@@@warning "-32"]
[@@@warning "-33"]

open Containers

let source_repository_path = Array.get Sys.argv 1
let destination_repository_path = Array.get Sys.argv 2
let cross_name = Array.get Sys.argv 3

let pp_arg fmt (arg, _) =
  match arg with
  | OpamTypes.CString x -> Format.fprintf fmt "\"%s\"" x
  | OpamTypes.CIdent x -> Format.fprintf fmt "<%s>" x

let pp_build fmt (args, _) =
  Format.fprintf fmt "%a"
    (Format.pp_print_list ~pp_sep:Format.pp_print_space pp_arg)
    args

module Solver = Opam_0install.Solver.Make (Opam_0install.Dir_context)

let map_package_roots source_repository_name overlay_repository_name
    destination_repository_path cross_name listed_packages =
  let open Containers.Result in
  let base_packages = [ "ocaml-cross-" ^ cross_name ] in
  let resolution =
    Package_resolve.resolve
      ~repositories:[ source_repository_name; overlay_repository_name ]
      ~listed_packages ~base_packages ()
  in
  Result.iter
    (fun resolution ->
      Printf.printf "Resolved packages:\n";
      OpamPackage.Set.iter
        (fun p -> Printf.printf "  - %s\n" (OpamPackage.to_string p))
        resolution)
    resolution

(**)
let main () =
  let open Cmdliner in
  let source_repository_name =
    let doc = "source repository name" in
    Arg.(
      required
      & pos 0 (some string) None
      & info [] ~docv:"SOURCE_REPOSITORY_NAME" ~doc)
  in
  let overlay_repository_name =
    let doc = "overlay repository name" in
    Arg.(
      required
      & pos 1 (some string) None
      & info [] ~docv:"OVERLAY_REPOSITORY_NAME" ~doc)
  in
  let destination_repository_path =
    let doc = "destination repository name" in
    Arg.(
      required
      & pos 1 (some string) None
      & info [] ~docv:"DESTINATION_REPOSITORY_NAME" ~doc)
  in
  let cross_name =
    let doc = "The cross compiler name / toolchain name" in
    Arg.(required & pos 2 (some string) None & info [] ~docv:"CROSS_NAME" ~doc)
  in
  let listed_packages =
    let doc = "packages to resolve" in
    Arg.(required & pos 3 (some (list string)) (Some []) & info [] ~doc)
  in
  let map_packages_t =
    Term.(
      const map_package_roots $ source_repository_name $ overlay_repository_name
      $ destination_repository_path $ cross_name $ listed_packages)
  in
  let map_packages_cmd =
    let doc =
      "produce a repository with -cross-<cross_name> packages and their \
       dependencies ready to install with opam"
    in
    let man = [] in
    let info = Cmd.info "map-packages" ~version:"%%VERSION%%" ~doc ~man in
    Cmd.v info map_packages_t
  in

  let info =
    let doc = "OCaml cross compilation package management utilities" in
    let man = [] in
    Cmd.info "packman" ~version:"%%VERSION%%" ~doc ~man
  in

  let g = Cmdliner.Cmd.group info [ map_packages_cmd ] in
  exit (Cmd.eval g)

let () = main ()
