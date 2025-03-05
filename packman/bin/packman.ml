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

let map_package_roots source_repository_path destination_repository_path
    cross_name listed_packages =
  let env =
    Opam_0install.Dir_context.std_env ~arch:"x86_64" ~os:"linux"
      ~os_family:"RedHat" ~os_distribution:"Amazon" ~os_version:"10"
      ~sys_ocaml_version:"5.3.0" ()
  in
  let constraints =
    OpamPackage.Name.(
      Map.empty
      |> Map.add (of_string "ocaml") (`Eq, OpamPackage.Version.of_string "5.3.0"))
  in
  let context =
    Opam_0install.Dir_context.create ~constraints ~env
      (source_repository_path ^ "/packages")
  in
  (* Parse package names into actual package requests *)
  let package_atoms =
    List.map
      (fun name ->
        (* match String.Split.left ~by:"." name with *)
        (* | Some (name, version) -> *)
        (*     ( OpamPackage.Name.of_string name, *)
        (*       Some (`Eq, OpamPackage.Version.of_string version) ) *)
        (* | None -> (OpamPackage.Name.of_string name, None)) *)
        OpamPackage.Name.of_string name)
      listed_packages
  in
  let result = Solver.solve context package_atoms in
  match result with
  | Error e -> print_endline (Solver.diagnostics e)
  | Ok selections ->
      Solver.packages_of_result selections
      |> List.iter (fun pkg ->
             Printf.printf "  - %s\n" (OpamPackage.to_string pkg))

let map_package_roots_old source_repository_path destination_repository_path
    cross_name listed_packages =
  let open OpamTypes in
  let open OpamSolver in
  let open OpamPackage in
  let open OpamStateTypes in
  let gt = OpamGlobalState.load `Lock_read in
  let default_repo_name = OpamRepositoryName.of_string "default" in
  let rt = OpamRepositoryState.load `Lock_read gt in
  let default_root = OpamRepositoryState.get_root rt default_repo_name in
  Printf.printf "Default root: %s\n" (OpamFilename.Dir.to_string default_root);
  let st =
    OpamSwitchState.load_virtual ~repos_list:[ default_repo_name ] gt rt
  in

  (* Create universe for the solver *)
  let package_set = OpamRepository.packages default_root in
  let universe = OpamSwitchState.universe ~requested:package_set st Query in

  (* Parse package names into actual package requests *)
  let package_atoms =
    List.map
      (fun name ->
        match String.Split.left ~by:"." name with
        | Some (name, version) ->
            ( OpamPackage.Name.of_string name,
              Some (`Eq, OpamPackage.Version.of_string version) )
        | None -> (OpamPackage.Name.of_string name, None))
      listed_packages
  in
  let solver =
    Lazy.from_fun (fun () ->
        OpamCudfSolver.solver_of_string "builtin-mccs+glpk")
  in
  let config = OpamSolverConfig.init in
  let () = config ~solver () in
  let requested =
    OpamSolver.request ~criteria:`Default ~install:package_atoms ()
  in

  (* Request the solver to find a solution *)
  match OpamSolver.resolve universe requested with
  | Success solution ->
      (* Extract the packages from the solution *)
      let packages = OpamSolver.all_packages solution in
      Printf.printf "Resolved packages:\n";
      OpamPackage.Set.iter
        (fun p -> Printf.printf "  - %s\n" (OpamPackage.to_string p))
        packages;
      ()
  | Conflicts conflicts ->
      Printf.printf "Could not resolve dependencies: conflicts detected\n";
      OpamCudf.string_of_conflicts OpamPackage.Set.empty (fun _ -> "") conflicts
      |> Printf.printf "%s\n";
      ()

(* let open OpamSolver in *)
(* let source_repository_dir = *)
(*   OpamFilename.Dir.of_string source_repository_path *)
(* in *)
(* let source_package_set = OpamRepository.packages source_repository_dir in *)
(* let universe = Op in *)
(* let universe = *)
(*   OpamSolver.load_cudf_universe universe source_package_set ~build:false *)
(*     ~post:false () *)
(* in *)
(* let install_formula = *)
(*   listed_packages |> List.map OpamFormula.atom_of_string *)
(* in *)
(* let resolve_request = request ~install:install_formula () in *)
(* Format.printf "Resolving %s\n" (string_of_request resolve_request); *)
(* let solution = reslove universe resolve_request in *)
(* let result_string = *)
(*   solution |> function *)
(*   | OpamTypes.Success solution -> *)
(*       "Solved: " ^ (solution_to_json solution |> OpamJson.to_string) *)
(*   | OpamTypes.Conflicts x -> "Conflict" *)
(* in *)
(* Format.printf "Solution %s\n" result_string; *)

(* Remap.opam_file ~source_repository_path ~destination_repository_path cross_name *)

(**)
let main () =
  let open Cmdliner in
  let source_repository_path =
    let doc = "The path to the source repository" in
    Arg.(
      required
      & pos 0 (some string) None
      & info [] ~docv:"SOURCE_REPOSITORY_PATH" ~doc)
  in
  let destination_repository_path =
    let doc = "The path to the destination repository" in
    Arg.(
      required
      & pos 1 (some string) None
      & info [] ~docv:"DESTINATION_REPOSITORY_PATH" ~doc)
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
      const map_package_roots_old
      $ source_repository_path $ destination_repository_path $ cross_name
      $ listed_packages)
  in
  let cmd =
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

  let g = Cmdliner.Cmd.group info [ cmd ] in
  exit (Cmd.eval g)

(* let opam = OpamFile.OPAM.read "opam" in *)
(* let name = OpamFile.OPAM.name opam in *)
(* let version = OpamFile.OPAM.version opam in *)

(* Format.printf "Name = %s\nVersion = %s\n" name version; *)
(**)
(* let build = OpamFile.OPAM.build opam in *)
(* Format.printf "Build\n%a" (Format.pp_print_list ~pp_sep:(fun fmt () -> Format.fprintf fmt "<newline>@\n") pp_build) build *)

let () = main ()
