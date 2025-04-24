[@@@warning "-27"]

open Containers

let filtered_formula_of_package ?var_constraint ~name ~version () =
  let open OpamTypes in
  let open OpamFormula in
  (* Define the package name and version constraint *)
  let package_name = OpamPackage.Name.of_string name in
  let version = OpamTypes.FString version in
  let version_constraint = Constraint (`Geq, version) in

  (* Create a condition using the version constraint *)
  let condition =
    match var_constraint with
    | Some var_name ->
        And
          ( Atom version_constraint,
            Atom
              (Filter
                 (OpamTypes.FIdent ([], OpamVariable.of_string var_name, None)))
          )
    | None -> Atom version_constraint
  in

  (* Construct the filtered formula using the package name and condition *)
  let filtered_formula : OpamTypes.filtered_formula =
    Atom (package_name, condition)
  in
  filtered_formula

let string_of_constraint =
  let open OpamTypes in
  OpamFormula.string_of_formula (function
    | Constraint (op, FString s) ->
        Printf.sprintf "(op:%s string:\"%s\")"
          (OpamPrinter.FullPos.relop_kind op)
          s
    | Constraint (op, (FIdent _ as v)) ->
        Printf.sprintf "(op:%s ident:%s)"
          (OpamPrinter.FullPos.relop_kind op)
          (OpamFilter.to_string v)
    | Constraint (op, v) ->
        Printf.sprintf "op:%s filter:(%s)"
          (OpamPrinter.FullPos.relop_kind op)
          (OpamFilter.to_string v)
    | Filter f -> "filter:" ^ OpamFilter.to_string f)

let rec has_filter s =
  OpamTypes.(
    function
    | FString _ -> false
    | FAnd (x, y) ->
        (* Printf.printf "FAnd"; *)
        has_filter s x || has_filter s y
    | FOr (x, y) ->
        (* Printf.printf "FOr"; *)
        has_filter s x || has_filter s y
    | FDefined x ->
        (* Printf.printf "FDefined"; *)
        has_filter s x
    | FOp (x, _, y) ->
        (* Printf.printf "FOp"; *)
        has_filter s x || has_filter s y
    | FIdent (_, v, _) ->
        String.equal (OpamVariable.to_string v) s
        (* Printf.printf "FIdent:%s:%s;" *)
        (*   (String.concat ", " *)
        (*      (names *)
        (*      |> List.map (function *)
        (*           | Some n -> OpamPackage.Name.to_string n *)
        (*           | None -> "<none>"))) *)
        (*   (OpamVariable.to_string v); *)
    | _ -> false)

let has_formula x fc =
  let open OpamTypes in
  let test_condition = function
    | Constraint (_, f) -> has_filter x f
    | Filter f -> has_filter x f
  in
  let res = OpamFormula.exists test_condition fc in
  (* Printf.printf "===\n"; *)
  res

let has_build_formula fc = has_formula "build" fc || has_formula "dev" fc
let has_dev_formula fc = has_formula "dev-setup" fc
let has_test_formula fc = has_formula "with-test" fc
let has_doc_formula fc = has_formula "with-doc" fc
let has_build_filter fc = has_filter "build" fc
let has_dev_filter fc = has_filter "dev-setup" fc || has_filter "dev" fc
let has_test_filter fc = has_filter "with-test" fc
let has_doc_filter fc = has_filter "with-doc" fc

let remap_depends ~cross depends =
  depends
  |> OpamFormula.map
     @@ fun ((name, fc) : OpamTypes.name * OpamTypes.condition) ->
     Format.printf "Name = %s, Condition = %s\n"
       (OpamPackage.Name.to_string name)
       (string_of_constraint fc);
     let name_s = OpamPackage.Name.to_string name in

     match name_s with
     | "dune" | "dune-configurator" -> Atom (name, fc)
     | "ocaml" -> Atom (Cross.map_package_name cross name, fc)
     | _ when has_dev_formula fc || has_test_formula fc || has_doc_formula fc ->
         Empty
     | _ when has_build_formula fc -> Atom (name, fc)
     | _ -> Atom (Cross.map_package_name cross name, fc)

let remap_no_build_install ~cross opam =
  let build = OpamFile.OPAM.build opam in
  let install = OpamFile.OPAM.install opam in
  match List.length build = 0 && List.length install = 0 with
  | true ->
      Format.printf "using remap_no_build_install\n";
      (* let target_depends = *)
      (*   opam |> OpamFile.OPAM.depends |> remap_depends ~cross *)
      (* in *)
      (* let opam = opam |> OpamFile.OPAM.with_depends target_depends in *)
      Some opam
  | false -> None

let remap_dune_install ~cross opam =
  let remap_build ~name ~cross (commands : OpamTypes.command list) =
    let name_s = OpamPackage.Name.to_string name in
    commands
    |> List.filter_map @@ fun (args, fc) ->
       if
         fc
         |> Option.map_or ~default:false @@ fun fc ->
            has_build_filter fc || has_dev_filter fc || has_test_filter fc
            || has_doc_filter fc
       then None
       else
         let open OpamTypes in
         Format.printf "using remap_dune_install\n";
         Some
           (match args with
           (* dune, in its standard incantation when generated from dune-project files *)
           | (CString "dune", f1)
             :: (CString "build", f2)
             :: (CString "-p", f3)
             :: (CIdent "name", f4)
             :: remaining ->
               ( (CString "dune", f1) :: (CString "build", f2)
                 :: (CString "-p", f3) :: (CString name_s, f4)
                 :: (CString "-x", None)
                 :: (CString (Cross.toolchain cross), None)
                 :: remaining,
                 fc )
           | _ ->
               failwith
                 "Package does not have a detectable dune-based build - create \
                  a cross-template for it")
  in

  match
    opam |> OpamFile.OPAM.depends
    |> OpamFormula.exists (fun (name, _) ->
           String.equal (OpamPackage.Name.to_string name) "dune")
  with
  | true ->
      let name = opam |> OpamFile.OPAM.name in
      (* let target_depends = *)
      (*   opam |> OpamFile.OPAM.depends |> remap_depends ~cross *)
      (* in *)
      let target_build =
        opam |> OpamFile.OPAM.build |> remap_build ~name ~cross
      in
      let opam =
        opam
        (* |> OpamFile.OPAM.with_depends target_depends *)
        |> OpamFile.OPAM.with_build target_build
      in
      Some opam
  | false -> None

let remap_topkg_install ~cross opam =
  let remap_build ~name ~cross (commands : OpamTypes.command list) =
    let name_s = OpamPackage.Name.to_string name in
    commands
    |> List.filter_map @@ fun (args, fc) ->
       if
         fc
         |> Option.map_or ~default:false @@ fun fc ->
            has_build_filter fc || has_dev_filter fc || has_test_filter fc
            || has_doc_filter fc
       then None
       else
         let open OpamTypes in
         Format.printf "using remap_topkg_install\n";
         Some
           (match args with
           (* topkg - used by the prolific erratique.ch who maintains several key OCaml libraries. topkg is now deprecated for new packages but remains in use for these existing packages. *)
           | (CString "ocaml", f1)
             :: (CString "pkg/pkg.ml", f2)
             :: (CString "build", f3)
             :: remaining ->
               ( (CString "ocaml", f1) :: (CString "pkg/pkg.ml", f2)
                 :: (CString "build", f3)
                 :: (CString "--toolchain", None)
                 :: (CString (Cross.toolchain cross), None)
                 :: (CString "--pkg-name", None)
                 :: (CString name_s, None) :: remaining,
                 fc )
           | _ ->
               failwith
                 "Package does not have a detectable topkg-based build - \
                  create a cross-template for it")
  in
  let remap_install ~name ~cross install =
    let name_s = OpamPackage.Name.to_string name in
    let open OpamTypes in
    if List.length install > 0 then
      failwith
        "Install commands already present for a topkg-based package install - \
         unable to remap";
    [
      ( [
          (CString "opam-installer", None);
          ( CString ("--prefix=%{prefix}%/" ^ Cross.toolchain cross ^ "-sysroot"),
            None );
          (CString (name_s ^ ".install"), None);
        ],
        None );
    ]
  in
  let remap_remove ~name ~cross remove =
    let open OpamTypes in
    let name_s = OpamPackage.Name.to_string name in
    if List.length remove > 0 then
      failwith
        "Remove commands already present for a topkg-based package install - \
         unable to remap";
    [
      ( [
          (CString "ocamlfind", None);
          (CString "-toolchain", None);
          (CString (Cross.toolchain cross), None);
          (CString "remove", None);
          (CString name_s, None);
        ],
        None );
    ]
  in
  match
    opam |> OpamFile.OPAM.depends
    |> OpamFormula.exists (fun (name, _) ->
           String.equal (OpamPackage.Name.to_string name) "topkg")
  with
  | true ->
      let name = opam |> OpamFile.OPAM.name in
      let target_build =
        opam |> OpamFile.OPAM.build |> remap_build ~name ~cross
      in
      let target_install =
        opam |> OpamFile.OPAM.install |> remap_install ~name ~cross
      in
      let target_remove =
        opam |> OpamFile.OPAM.remove |> remap_remove ~name ~cross
      in
      let extra_depends =
        filtered_formula_of_package ~name:"opam-installer" ~version:"2.0.0"
          ~var_constraint:"build" ()
      in
      let depends_list = opam |> OpamFile.OPAM.depends in
      let opam =
        opam
        |> OpamFile.OPAM.with_build target_build
        |> OpamFile.OPAM.with_install target_install
        |> OpamFile.OPAM.with_remove target_remove
        |> OpamFile.OPAM.with_depends
             (OpamFormula.And (depends_list, extra_depends))
      in
      Some opam
  | false -> None

let remap_package_variables_in_commands ~cross commands =
  let open OpamTypes in
  let remap_package_variables s =
    let available_package_variables =
      [
        "name";
        "version";
        "depends";
        "installed";
        "enable";
        "pinned";
        "bin";
        "sbin";
        "lib";
        "man";
        "doc";
        "share";
        "build";
        "hash";
        "dev";
        "build-id";
        "opamfile";
      ]
    in
    Opam_helpers.map_variables s @@ fun (var_name, package_name) ->
    match List.exists (String.equal var_name) available_package_variables with
    | true ->
        ( var_name,
          Cross.map_package_name cross (OpamPackage.Name.of_string package_name)
          |> OpamPackage.Name.to_string )
    | false -> (var_name, package_name)
  in
  commands
  |> List.map @@ fun ((args, fc) : OpamTypes.command) ->
     let args =
       args
       |> List.map @@ fun (arg, fc2) ->
          match arg with
          | CString s -> (CString (remap_package_variables s), fc2)
          | _ -> (arg, fc2)
     in
     (args, fc)

let opam_file ~source_repository_name ~destination_repository_path ~package
    ~cross () =
  try
    let gt = OpamGlobalState.load `Lock_read in
    let rt = OpamRepositoryState.load `Lock_read gt in
    let source_repository_path =
      source_repository_name |> OpamRepositoryName.of_string
      |> OpamRepositoryState.get_root rt
    in
    let package_name = OpamPackage.name_to_string package in

    let file =
      OpamRepositoryPath.opam source_repository_path (Some package_name) package
    in
    Printf.printf "opam_file: remapping %s\n" (OpamFile.to_string file);
    let opam = file |> OpamFile.OPAM.read in
    let name = OpamFile.OPAM.name opam in
    let target_name = name |> Cross.map_package_name cross in
    let target_depends =
      opam |> OpamFile.OPAM.depends |> remap_depends ~cross
    in
    let opam = opam |> OpamFile.OPAM.with_depends target_depends in
    let opam =
      [ remap_no_build_install; remap_dune_install; remap_topkg_install ]
      |> List.find_map (fun remapper -> remapper ~cross opam)
      |> Option.get_exn_or "Unknown build system used in opam file"
    in
    (* remap the name and dependencies last so that the remappers have access
       to the original name and dependencies *)
    let opam =
      opam
      |> OpamFile.OPAM.with_name target_name
      |> OpamFile.OPAM.with_install
           (OpamFile.OPAM.install opam
           |> remap_package_variables_in_commands ~cross)
      |> OpamFile.OPAM.with_build
           (OpamFile.OPAM.build opam
           |> remap_package_variables_in_commands ~cross)
    in
    let destination_package_name = target_name in
    let destination_package =
      OpamPackage.create destination_package_name (OpamPackage.version package)
    in
    let destination_package_path =
      OpamRepositoryPath.opam destination_repository_path
        (Some (OpamPackage.Name.to_string destination_package_name))
        destination_package
    in
    let destination_file =
      OpamFile.make (OpamFile.filename destination_package_path)
    in
    Printf.printf "opam_file: writing to %s\n"
      (OpamFile.to_string destination_file);
    OpamFile.OPAM.write destination_file opam;
    Ok ()
  with
  | Failure s -> Error ("Failed to remap opam file: " ^ s)
  | _ as e -> Error ("Failed to remap opam file: " ^ Printexc.exn_slot_name e)
