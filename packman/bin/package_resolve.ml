open Containers

let resolve_package_set ~install ~with_error_message universe =
  let requested = OpamSolver.request ~criteria:`Default ~install () in

  (* Request the solver to find a solution *)
  match OpamSolver.resolve universe requested with
  | Success solution ->
      (* Extract the packages from the solution *)
      let packages = OpamSolver.all_packages solution in
      Ok packages
  | Conflicts conflicts ->
      let conflicts =
        OpamCudf.string_of_conflicts OpamPackage.Set.empty
          (fun (name, _) ->
            "Unable to locate package " ^ OpamPackage.Name.to_string name)
          conflicts
      in
      Error (with_error_message ^ ": " ^ conflicts)

let resolve ~repositories ~listed_packages ~base_packages () =
  let open OpamTypes in
  let gt = OpamGlobalState.load `Lock_read in
  let rt = OpamRepositoryState.load `Lock_read gt in
  (* let global_state = OpamStateConfig.init () in *)
  (* let gt = global_state in *)
  let repositories = repositories |> List.map OpamRepositoryName.of_string in

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

  (* initialise the solver explicitly otherwise OpamSolver will throw on "no criteria" *)
  let solver_init = OpamSolverConfig.init in
  solver_init ~solver ();

  (* Compute the set of packages we want to rewrite as cross packages
     We do this by computing two sets and finding the difference:
     1. compiler_set: the cross-compiler and everything it depends upon
     2. full_set: the full set of packages and their transitive dependencies
     *)
  let compiler_set =
    resolve_package_set ~install:installed_package_atoms
      ~with_error_message:"Unable to resolve cross-compiler package" universe
  in
  let full_set =
    resolve_package_set
      ~install:(List.concat [ installed_package_atoms; package_atoms ])
      ~with_error_message:"Unable to resolve requested packages" universe
  in
  Result.both full_set compiler_set
  |> Result.map (fun (full_set, compiler_set) ->
         OpamPackage.Set.diff full_set compiler_set)
