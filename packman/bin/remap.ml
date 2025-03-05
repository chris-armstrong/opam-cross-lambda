open Containers

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

let remap_depends cross_suffix depends =
  depends
  |> OpamFormula.map
     @@ fun ((name, fc) : OpamTypes.name * OpamTypes.condition) ->
     Format.printf "Name = %s, Condition = %s\n"
       (OpamPackage.Name.to_string name)
       (string_of_constraint fc);
     let name_s = OpamPackage.Name.to_string name in

     match name_s with
     | "dune" -> Atom (name, fc)
     | "ocaml" -> Atom (OpamPackage.Name.of_string (name_s ^ cross_suffix), fc)
     | _
       when has_build_formula fc || has_dev_formula fc || has_test_formula fc
            || has_doc_formula fc ->
         Empty
     | _ -> Atom (OpamPackage.Name.of_string (name_s ^ cross_suffix), fc)

let remap_build ~name ~cross_name (commands : OpamTypes.command list) =
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
       Some
         (match args with
         | (CString "dune", f1)
           :: (CString "build", f2)
           :: (CString "-p", f3)
           :: (CIdent "name", f4)
           :: remaining ->
             ( (CString "dune", f1) :: (CString "build", f2)
               :: (CString "-p", f3) :: (CString name_s, f4)
               :: (CString "-x", None) :: (CString cross_name, None)
               :: remaining,
               fc )
         | _ -> (args, fc))

let remap_name ~cross_suffix name =
  let name_s = OpamPackage.Name.to_string name in
  OpamPackage.Name.of_string (name_s ^ cross_suffix)

let opam_file ~source_repository_path ~destination_repository_path ~package_name
    ~package_version ~cross_name () =
  let package_path =
    OpamFilename.Op.(
      OpamFilename.Dir.of_string source_repository_path
      / "packages" / package_name
      / (package_name ^ "." ^ package_version))
  in

  let file = OpamFile.make OpamFilename.Op.(package_path // "opam") in
  let opam = file |> OpamFile.OPAM.read in
  let name = opam |> OpamFile.OPAM.name in
  let cross_suffix = Names.cross_suffix cross_name in
  let target_depends =
    opam |> OpamFile.OPAM.depends |> remap_depends cross_suffix
  in
  let target_build =
    opam |> OpamFile.OPAM.build |> remap_build ~name ~cross_name
  in
  let target_name = name |> remap_name ~cross_suffix in
  let opam =
    opam
    |> OpamFile.OPAM.with_depends target_depends
    |> OpamFile.OPAM.with_name target_name
    |> OpamFile.OPAM.with_build target_build
  in
  let destination_package_name = package_name ^ cross_suffix in
  let destination_package_path =
    OpamFilename.Op.(
      OpamFilename.Dir.of_string destination_repository_path
      / "packages" / destination_package_name
      / (destination_package_name ^ "." ^ package_version)
      // "opam")
  in
  let destination_file = OpamFile.make destination_package_path in
  OpamFile.OPAM.write destination_file opam
