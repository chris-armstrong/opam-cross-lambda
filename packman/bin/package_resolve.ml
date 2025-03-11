open Containers

let resolve ~repositories ~listed_packages ~base_packages () =
  let open OpamTypes in
  let gt = OpamGlobalState.load `Lock_read in
  (* let global_state = OpamStateConfig.init () in *)
  (* let gt = global_state in *)
  let repositories = repositories |> List.map OpamRepositoryName.of_string in
  let rt = OpamRepositoryState.load `Lock_read gt in

  (* Create universe for the solver *)
  let package_set = OpamPackage.Set.empty in
  let st = OpamSwitchState.load_virtual ~repos_list:repositories gt rt in
  let universe = OpamSwitchState.universe ~requested:package_set st Query in

  (* Parse package names into actual package requests *)
  let installed_package_atoms =
    List.map
      (fun name ->
        match String.Split.left ~by:"." name with
        | Some (name, version) ->
            ( OpamPackage.Name.of_string name,
              Some (`Eq, OpamPackage.Version.of_string version) )
        | None -> (OpamPackage.Name.of_string name, None))
      base_packages
  in
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
    Lazy.from_fun (fun () -> OpamCudfSolver.solver_of_string "builtin-0install")
  in
  let solver_init = OpamSolverConfig.init in
  solver_init ~solver ();
  let full_set =
    let requested =
      OpamSolver.request ~criteria:`Default
        ~install:(List.concat [ installed_package_atoms; package_atoms ])
        ()
    in

    (* Request the solver to find a solution *)
    match OpamSolver.resolve universe requested with
    | Success solution ->
        (* Extract the packages from the solution *)
        let packages = OpamSolver.all_packages solution in
        Ok packages
    | Conflicts conflicts ->
        Printf.printf "Could not resolve dependencies: conflicts detected\n";
        let conflicts =
          OpamCudf.string_of_conflicts OpamPackage.Set.empty
            (fun (name, _) ->
              "Unable to locate package " ^ OpamPackage.Name.to_string name)
            conflicts
        in
        conflicts |> Printf.printf "%s\n";
        Error conflicts
  in
  let compiler_set =
    let requested =
      OpamSolver.request ~criteria:`Default ~install:installed_package_atoms ()
    in
    (* Request the solver to find a solution *)
    match OpamSolver.resolve universe requested with
    | Success solution ->
        (* Extract the packages from the solution *)
        let packages = OpamSolver.all_packages solution in
        Ok packages
    | Conflicts conflicts ->
        Printf.printf "Could not resolve dependencies: conflicts detected\n";
        let conflicts =
          OpamCudf.string_of_conflicts OpamPackage.Set.empty
            (fun (name, _) ->
              "Unable to locate package " ^ OpamPackage.Name.to_string name)
            conflicts
        in
        conflicts |> Printf.printf "%s\n";
        Error conflicts
  in
  Result.both full_set compiler_set
  |> Result.map (fun (full_set, compiler_set) ->
         OpamPackage.Set.diff full_set compiler_set)
