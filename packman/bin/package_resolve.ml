open Containers

module CustomOpamSolver = struct
  open OpamTypes
  open OpamPackage.Set.Op

  type solution = OpamCudf.ActionGraph.t

  let resolve universe request =
    let log fmt = OpamConsole.log "SOLVER" fmt in
    let slog = OpamConsole.slog in

    log "resolve request=%a" (slog OpamSolver.string_of_request) request;
    let all_packages =
      Lazy.force universe.u_available ++ universe.u_installed
    in
    let version_map = OpamSolver.cudf_versions_map universe in

    let univ_gen =
      OpamSolver.load_cudf_universe universe ~version_map all_packages
    in
    let cudf_universe = univ_gen ~depopts:false ~build:false ~post:true () in

    let requested_names =
      OpamPackage.Name.Set.of_list (List.map fst request.wish_all)
    in
    let request = { request with extra_attributes = [] } in

    let map_request f r =
      let fl = List.rev_map f in
      {
        wish_install = OpamFormula.map (fun x -> Atom (f x)) r.wish_install;
        wish_remove = fl r.wish_remove;
        wish_upgrade = fl r.wish_upgrade;
        wish_all = fl r.wish_all;
        criteria = r.criteria;
        extra_attributes = r.extra_attributes;
      }
    in

    let name_to_cudf name =
      let name_s = OpamPackage.Name.to_string name in
      if
        OpamStd.String.for_all
          (function
            | 'a' .. 'z'
            | 'A' .. 'Z'
            | '0' .. '9'
            | '@' | '/' | '+' | '(' | ')' | '.' | '-' ->
                true
            | _ -> false)
          name_s
      then name_s
      else Dose_common.CudfAdd.encode name_s
    in

    let constraint_to_cudf version_map name (op, v) =
      let nv = OpamPackage.create name v in
      try Some (op, OpamPackage.Map.find nv version_map)
      with Not_found -> Some (`Gt, 0)
    in

    let atom2cudf _universe (version_map : int OpamPackage.Map.t) (name, cstr) =
      ( name_to_cudf name,
        OpamStd.Option.Op.(cstr >>= constraint_to_cudf version_map name) )
    in

    let cudf_request = map_request (atom2cudf universe version_map) request in

    let solution =
      try
        let resp =
          OpamCudf.resolve ~extern:true ~version_map cudf_universe cudf_request
        in
        OpamCudf.to_actions cudf_universe resp
      with OpamCudf.Solver_failure msg ->
        let bt = Printexc.get_raw_backtrace () in
        OpamConsole.error "%s" msg;
        Printexc.raise_with_backtrace
          OpamStd.Sys.(Exit (get_exit_code `Solver_failure))
          bt
    in

    match solution with
    | Conflicts _ as c -> c
    | Success actions -> (
        let simple_universe =
          univ_gen ~depopts:true ~build:false ~post:false ()
        in
        let complete_universe =
          univ_gen ~depopts:true ~build:false ~post:false ()
        in
        try
          let atomic_actions =
            OpamCudf.atomic_actions ~simple_universe ~complete_universe actions
          in
          OpamCudf.trim_actions cudf_universe requested_names atomic_actions;
          Success atomic_actions
        with OpamCudf.Cyclic_actions cycles ->
          OpamCudf.cycle_conflict ~version_map complete_universe cycles)
end

module CustomOpamSolver2 = struct
  open OpamTypes
  open OpamPackage.Set.Op

  type solution = OpamCudf.ActionGraph.t

  let resolve universe request =
    let log fmt = OpamConsole.log "SOLVER" fmt in
    let slog = OpamConsole.slog in

    log "resolve request=%a" (slog OpamSolver.string_of_request) request;
    let all_packages =
      Lazy.force universe.u_available ++ universe.u_installed
    in
    let version_map = OpamSolver.cudf_versions_map universe in

    let univ_gen =
      OpamSolver.load_cudf_universe universe ~version_map all_packages
    in
    let cudf_universe = univ_gen ~depopts:false ~build:false ~post:true () in

    let requested_names =
      OpamPackage.Name.Set.of_list (List.map fst request.wish_all)
    in

    let name_to_cudf name =
      let name_s = OpamPackage.Name.to_string name in
      if
        OpamStd.String.for_all
          (function
            | 'a' .. 'z'
            | 'A' .. 'Z'
            | '0' .. '9'
            | '@' | '/' | '+' | '(' | ')' | '.' | '-' ->
                true
            | _ -> false)
          name_s
      then name_s
      else Dose_common.CudfAdd.encode name_s
    in

    let constraint_to_cudf version_map name (op, v) =
      let nv = OpamPackage.create name v in
      try Some (op, OpamPackage.Map.find nv version_map)
      with Not_found -> Some (`Gt, 0)
    in

    let atom2cudf _universe (version_map : int OpamPackage.Map.t) (name, cstr) =
      ( name_to_cudf name,
        OpamStd.Option.Op.(cstr >>= constraint_to_cudf version_map name) )
    in

    let map_request f r =
      let fl = List.rev_map f in
      {
        wish_install = OpamFormula.map (fun x -> Atom (f x)) r.wish_install;
        wish_remove = fl r.wish_remove;
        wish_upgrade = fl r.wish_upgrade;
        wish_all = fl r.wish_all;
        criteria = r.criteria;
        extra_attributes = r.extra_attributes;
      }
    in

    let cudf_request = map_request (atom2cudf universe version_map) request in

    let solution =
      try
        let resp =
          OpamCudf.resolve ~extern:true ~version_map cudf_universe cudf_request
        in
        OpamCudf.to_actions cudf_universe resp
      with OpamCudf.Solver_failure msg ->
        let bt = Printexc.get_raw_backtrace () in
        OpamConsole.error "%s" msg;
        Printexc.raise_with_backtrace
          OpamStd.Sys.(Exit (get_exit_code `Solver_failure))
          bt
    in

    match solution with
    | Conflicts _ as c -> c
    | Success actions -> (
        let simple_universe =
          univ_gen ~depopts:true ~build:false ~post:false ()
        in
        let complete_universe =
          univ_gen ~depopts:true ~build:false ~post:false ()
        in
        try
          let atomic_actions =
            OpamCudf.atomic_actions ~simple_universe ~complete_universe actions
          in
          OpamCudf.trim_actions cudf_universe requested_names atomic_actions;
          Success atomic_actions
        with OpamCudf.Cyclic_actions cycles ->
          OpamCudf.cycle_conflict ~version_map complete_universe cycles)
end

(** A cloned version of OpamSolver with modifications to the resolve function to
    not bring in build dependencies. The actual workings are a bit mysterious as
    they were pulled together by Claude-Sonnet-3.7 *)
(* module CustomOpamSolver = struct *)
(*   open OpamTypes *)
(**)
(*   (* open OpamTypesBase *) *)
(*   open OpamPackage.Set.Op *)
(**)
(*   type solution = OpamCudf.ActionGraph.t *)
(**)
(*   (* Clone of the main resolve function with ~build:false modification *) *)
(*   let resolve universe request = *)
(*     let log fmt = OpamConsole.log "SOLVER" fmt in *)
(*     let slog = OpamConsole.slog in *)
(**)
(*     log "resolve request=%a" (slog OpamSolver.string_of_request) request; *)
(*     let all_packages = *)
(*       Lazy.force universe.u_available ++ universe.u_installed *)
(*     in *)
(*     let version_map = OpamSolver.cudf_versions_map universe in *)
(**)
(*     (* Key modification: use load_cudf_universe with ~build:false instead of true *) *)
(*     let univ_gen = *)
(*       OpamSolver.load_cudf_universe universe ~version_map all_packages *)
(*     in *)
(*     let cudf_universe = univ_gen ~depopts:false ~build:false ~post:true () in *)
(**)
(*     let requested_names = *)
(*       OpamPackage.Name.Set.of_list (List.map fst request.wish_all) *)
(*     in *)
(*     let request = *)
(*       let extra_attributes = *)
(*         OpamStd.List.sort_nodup String.compare *)
(*           (List.map fst universe.u_attrs @ request.extra_attributes) *)
(*       in *)
(*       { request with extra_attributes } *)
(*     in *)
(**)
(*     (* Create request and deprequest_pkg - using functions from opamSolver.ml *) *)
(*     let request, deprequest_pkg = *)
(*       let conj = OpamFormula.ands_to_list request.wish_install in *)
(*       let conj, deprequest = *)
(*         List.partition (function Atom _ -> true | _ -> false) conj *)
(*       in *)
(*       (* Clone of opam_deprequest_package from the original *) *)
(*       let opam_deprequest_package version_map deps = *)
(*         let opam_constraint_package version_map deps label package = *)
(*           let deps = *)
(*             deps *)
(*             |> OpamFormula.map (fun at -> *)
(*                    let name_to_cudf name = *)
(*                      let name_s = OpamPackage.Name.to_string name in *)
(*                      if *)
(*                        OpamStd.String.for_all *)
(*                          (function *)
(*                            | 'a' .. 'z' *)
(*                            | 'A' .. 'Z' *)
(*                            | '0' .. '9' *)
(*                            | '@' | '/' | '+' | '(' | ')' | '.' | '-' -> *)
(*                                true *)
(*                            | _ -> false) *)
(*                          name_s *)
(*                      then name_s *)
(*                      else Dose_common.CudfAdd.encode name_s *)
(*                    in *)
(*                    let constraint_to_cudf version_map name (op, v) = *)
(*                      let nv = OpamPackage.create name v in *)
(*                      try Some (op, OpamPackage.Map.find nv version_map) *)
(*                      with Not_found -> *)
(*                        (* Fallback logic for missing version *) *)
(*                        None *)
(*                    in *)
(*                    let atom2cudf _universe (version_map : int OpamPackage.Map.t) *)
(*                        (name, cstr) = *)
(*                      ( name_to_cudf name, *)
(*                        OpamStd.Option.Op.( *)
(*                          cstr >>= constraint_to_cudf version_map name) ) *)
(*                    in *)
(*                    Atom (atom2cudf () version_map at)) *)
(*             |> OpamFormula.cnf_of_formula |> OpamFormula.ands_to_list *)
(*             |> List.map (OpamFormula.fold_right (fun acc x -> x :: acc) []) *)
(*           in *)
(*           { *)
(*             Cudf.package = fst package; *)
(*             version = snd package; *)
(*             depends = deps; *)
(*             conflicts = []; *)
(*             provides = []; *)
(*             installed = true; *)
(*             was_installed = true; *)
(*             keep = `Keep_version; *)
(*             pkg_extra = *)
(*               [ *)
(*                 (OpamCudf.s_source, `String label); *)
(*                 (OpamCudf.s_source_number, `String "NULL"); *)
(*               ]; *)
(*           } *)
(*         in *)
(*         opam_constraint_package version_map deps "DEP_REQUEST" *)
(*           OpamCudf.opam_deprequest_package *)
(*       in *)
(*       ( { request with wish_install = OpamFormula.ands conj }, *)
(*         opam_deprequest_package version_map (OpamFormula.ands deprequest) ) *)
(*     in *)
(**)
(*     (* Clone of map_request and related functions *) *)
(*     let map_request f r = *)
(*       let fl = List.rev_map f in *)
(*       { *)
(*         wish_install = OpamFormula.map (fun x -> Atom (f x)) r.wish_install; *)
(*         wish_remove = fl r.wish_remove; *)
(*         wish_upgrade = fl r.wish_upgrade; *)
(*         wish_all = fl r.wish_all; *)
(*         criteria = r.criteria; *)
(*         extra_attributes = r.extra_attributes; *)
(*       } *)
(*     in *)
(**)
(*     let name_to_cudf name = *)
(*       let name_s = OpamPackage.Name.to_string name in *)
(*       if *)
(*         OpamStd.String.for_all *)
(*           (function *)
(*             | 'a' .. 'z' *)
(*             | 'A' .. 'Z' *)
(*             | '0' .. '9' *)
(*             | '@' | '/' | '+' | '(' | ')' | '.' | '-' -> *)
(*                 true *)
(*             | _ -> false) *)
(*           name_s *)
(*       then name_s *)
(*       else Dose_common.CudfAdd.encode name_s *)
(*     in *)
(**)
(*     let constraint_to_cudf version_map name (op, v) = *)
(*       let nv = OpamPackage.create name v in *)
(*       try Some (op, OpamPackage.Map.find nv version_map) *)
(*       with Not_found -> ( *)
(*         (* Simplified fallback for constraint handling *) *)
(*         match op with *)
(*         | `Neq -> None *)
(*         | _ -> Some (`Gt, 0)) *)
(*     in *)
(**)
(*     let atom2cudf _universe (version_map : int OpamPackage.Map.t) (name, cstr) = *)
(*       ( name_to_cudf name, *)
(*         OpamStd.Option.Op.(cstr >>= constraint_to_cudf version_map name) ) *)
(*     in *)
(**)
(*     let cudf_request = map_request (atom2cudf universe version_map) request in *)
(**)
(*     (* Clone of opam_invariant_package *) *)
(*     let opam_invariant_package version_map deps = *)
(*       let opam_constraint_package version_map deps label package = *)
(*         let deps = *)
(*           deps *)
(*           |> OpamFormula.map (fun at -> Atom (atom2cudf () version_map at)) *)
(*           |> OpamFormula.cnf_of_formula |> OpamFormula.ands_to_list *)
(*           |> List.map (OpamFormula.fold_right (fun acc x -> x :: acc) []) *)
(*         in *)
(*         { *)
(*           Cudf.package = fst package; *)
(*           version = snd package; *)
(*           depends = deps; *)
(*           conflicts = []; *)
(*           provides = []; *)
(*           installed = true; *)
(*           was_installed = true; *)
(*           keep = `Keep_version; *)
(*           pkg_extra = *)
(*             [ *)
(*               (OpamCudf.s_source, `String label); *)
(*               (OpamCudf.s_source_number, `String "NULL"); *)
(*             ]; *)
(*         } *)
(*       in *)
(*       opam_constraint_package version_map *)
(*         (OpamFormula.to_atom_formula deps) *)
(*         "SWITCH_INVARIANT" OpamCudf.opam_invariant_package *)
(*     in *)
(**)
(*     let invariant_pkg = *)
(*       opam_invariant_package version_map universe.u_invariant *)
(*     in *)
(**)
(**)
(*     let solution = *)
(*       try *)
(*         Cudf.add_package cudf_universe invariant_pkg; *)
(*         Cudf.add_package cudf_universe deprequest_pkg; *)
(*         let resp = *)
(*           OpamCudf.resolve ~extern:true ~version_map cudf_universe cudf_request *)
(*         in *)
(*         Cudf.remove_package cudf_universe OpamCudf.opam_deprequest_package; *)
(*         Cudf.remove_package cudf_universe OpamCudf.opam_invariant_package; *)
(*         OpamCudf.to_actions cudf_universe resp *)
(*       with OpamCudf.Solver_failure msg -> *)
(*         let bt = Printexc.get_raw_backtrace () in *)
(*         OpamConsole.error "%s" msg; *)
(*         Printexc.raise_with_backtrace *)
(*           OpamStd.Sys.(Exit (get_exit_code `Solver_failure)) *)
(*           bt *)
(*     in *)
(**)
(*     match solution with *)
(*     | Conflicts _ as c -> c *)
(*     | Success actions -> ( *)
(*         (* Second key modification: use ~build:false for both universes *) *)
(*         let simple_universe = *)
(*           univ_gen ~depopts:true ~build:false ~post:false () *)
(*         in *)
(*         let complete_universe = *)
(*           univ_gen ~depopts:true ~build:false ~post:false () *)
(*         in *)
(*         try *)
(*           let atomic_actions = *)
(*             OpamCudf.atomic_actions ~simple_universe ~complete_universe actions *)
(*           in *)
(*           OpamCudf.trim_actions cudf_universe requested_names atomic_actions; *)
(*           Success atomic_actions *)
(*         with OpamCudf.Cyclic_actions cycles -> *)
(*           (* Use cycle_conflict from OpamSolver *) *)
(*           let cycle_conflict ~version_map univ cycles = *)
(*             OpamCudf.cycle_conflict ~version_map univ cycles *)
(*           in *)
(*           cycle_conflict ~version_map complete_universe cycles) *)
(* end *)

let resolve_package_set ~install ~with_error_message universe =
  let requested = OpamSolver.request ~criteria:`Default ~install () in

  (* Request the solver to find a solution *)
  match CustomOpamSolver2.resolve universe requested with
  | Success solution ->
      (* Extract the packages from the solution *)
      let packages = OpamSolver.all_packages (Obj.magic solution) in
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

  (* Create universe for the solver *)
  let package_set = OpamPackage.Set.empty in
  let st = OpamSwitchState.load_virtual ~repos_list:repositories gt rt in
  let universe = OpamSwitchState.universe ~requested:package_set st Query in

  (* Parse package names into constraint atoms *)
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
