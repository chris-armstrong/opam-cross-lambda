[@@@warning "-26"]
[@@@warning "-27"]
[@@@warning "-32"]
[@@@warning "-33"]

open Containers

let setup_log style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (Logs_fmt.reporter ())

module Logs =
  (val Logs.src_log
         (Logs.Src.create
            ~doc:
              "Packman utility for building cross-compile version of an opam \
               file"
            "Packman"))

let pp_arg fmt (arg, _) =
  match arg with
  | OpamTypes.CString x -> Format.fprintf fmt "\"%s\"" x
  | OpamTypes.CIdent x -> Format.fprintf fmt "<%s>" x

let pp_build fmt (args, _) =
  Format.fprintf fmt "%a"
    (Format.pp_print_list ~pp_sep:Format.pp_print_space pp_arg)
    args

module Solver = Opam_0install.Solver.Make (Opam_0install.Dir_context)

let build_time_packages =
  [ "dune"; "ocamlbuild"; "ocamlfind"; "dune-configurator" ]

let map_package_roots _ source_repository_name overlay_repository_name
    cross_template_repository_path destination_repository_path cross_name
    listed_packages =
  let open Containers.Result in
  Logs.debug (fun m ->
      m
        "map_package_roots: source_repository_name=%s \
         overlay_repository_name=%s cross_template_repository_path=%s \
         destination_repository_path=%s cross_name=%s listed_packages=%a"
        source_repository_name overlay_repository_name
        cross_template_repository_path destination_repository_path cross_name
        (Format.list Fmt.string) listed_packages);
  let cross = Cross.of_string cross_name in
  let destination_repository_path =
    OpamFilename.Dir.of_string destination_repository_path
  in
  let repositories =
    [ source_repository_name; overlay_repository_name ]
    |> List.map OpamRepositoryName.of_string
  in
  let base_packages =
    [
      Cross.map_package_name cross (OpamPackage.Name.of_string "ocaml")
      |> OpamPackage.Name.to_string;
    ]
  in
  match
    let* resolved_packages =
      Package_resolve.resolve ~repositories ~listed_packages ~base_packages ()
    in

    Logs.info (fun m ->
        m "map_package_roots: resolved packages: %a"
          (Format.pp_print_list ~pp_sep:Fmt.comma
             (Fmt.of_to_string OpamPackage.to_string))
          (resolved_packages |> OpamPackage.Set.to_list));
    let packages_to_rewrite =
      OpamPackage.Set.filter
        (fun package ->
          let name = OpamPackage.name package in
          let version = OpamPackage.version package in
          let package_name = OpamPackage.Name.to_string name in
          let package_version = OpamPackage.Version.to_string version in
          build_time_packages
          |> List.exists (fun name -> String.equal package_name name)
          |> not)
        resolved_packages
    in
    let succeeded, failed =
      packages_to_rewrite |> OpamPackage.Set.to_seq
      |> Seq.map (fun package ->
             let name = OpamPackage.name package in
             let name_s = OpamPackage.Name.to_string name in
             (let has_template =
                Apply_cross_template.has_template
                  ~cross_template_repository_path package
              in
              Logs.info (fun m ->
                  m "map_package_roots: package %s %s template" name_s
                    (if has_template then "has" else "does not have"));
              if has_template then
                Apply_cross_template.apply_cross_template
                  ~cross_template_repository_path ~destination_repository_path
                  ~cross package
              else
                Remap.opam_file ~source_repository_name
                  ~destination_repository_path ~package ~cross ())
             |> map (fun () -> name_s)
             |> map_err (fun error -> (name_s, error)))
      |> Seq.fold
           (fun (succeeded, failed) res ->
             match res with
             | Ok package_name -> (package_name :: succeeded, failed)
             | Error failure -> (succeeded, failure :: failed))
           ([], [])
    in
    Fmt.pr "Successfully remapped packages: %a\n"
      (Format.pp_print_list ~pp_sep:Fmt.comma Format.pp_print_string)
      succeeded;
    Fmt.pr "\nFailures: \n";
    List.iter
      (fun (package_name, error) -> Fmt.pr "  - %s: %s\n" package_name error)
      failed;
    OpamFile.Repo.create ()
    |> OpamFile.Repo.write (OpamRepositoryPath.repo destination_repository_path);
    Ok ()
  with
  | Ok _ -> ()
  | Error error -> Printf.printf "Error: %s\n" error

(** Map the base compiler packages into destination repository *)
let map_base_packages _ source_repository_name overlay_repository_name
    destination_repository_path cross_name =
  let open Containers.Result in
  let cross = Cross.of_string cross_name in
  let destination_repository_path =
    OpamFilename.Dir.of_string destination_repository_path
  in
  let repositories =
    [ source_repository_name; overlay_repository_name ]
    |> List.map OpamRepositoryName.of_string
  in
  let base_packages =
    [
      Cross.map_package_name cross (OpamPackage.Name.of_string "ocaml")
      |> OpamPackage.Name.to_string;
    ]
  in
  let listed_packages =
    [
      "base-unix";
      "base-threads";
      "base-bigarray";
      "base-domains";
      "base-effects";
      "base-nnp";
    ]
  in
  let packages_to_rewrite =
    List.map
      (fun package -> OpamPackage.of_string (package ^ ".base"))
      listed_packages
  in
  let succeeded, failed =
    packages_to_rewrite |> List.to_seq
    |> Seq.map (fun package ->
           let name = OpamPackage.name package in
           let name_s = OpamPackage.Name.to_string name in
           Remap.opam_file ~source_repository_name ~destination_repository_path
             ~package ~cross ()
           |> map (fun () -> name_s)
           |> map_err (fun error -> (name_s, error)))
    |> Seq.fold
         (fun (succeeded, failed) res ->
           match res with
           | Ok package_name -> (package_name :: succeeded, failed)
           | Error failure -> (succeeded, failure :: failed))
         ([], [])
  in
  Fmt.pr "Successfully remapped packages: %a\n"
    (Format.pp_print_list ~pp_sep:Fmt.comma Format.pp_print_string)
    succeeded;
  Fmt.pr "\nFailures: \n";
  List.iter
    (fun (package_name, error) -> Fmt.pr "  - %s: %s\n" package_name error)
    failed;
  OpamFile.Repo.create ()
  |> OpamFile.Repo.write (OpamRepositoryPath.repo destination_repository_path)

(**)
let main () =
  let open Cmdliner in
  let setup_log =
    let env = Cmd.Env.info "PACKMAN_LOG_LEVEL" ~doc:"Set the log level" in
    Term.(const setup_log $ Fmt_cli.style_renderer () $ Logs_cli.level ~env ())
  in

  let map_packages_t =
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
    let cross_template_repository_path =
      let doc = "path to cross-template repository" in
      Arg.(
        required
        & pos 2 (some string) None
        & info [] ~docv:"CROSS_TEMPLATE_REPOSITORY_PATH" ~doc)
    in
    let destination_repository_path =
      let doc = "destination repository path" in
      Arg.(
        required
        & pos 3 (some string) None
        & info [] ~docv:"DESTINATION_REPOSITORY_PATH" ~doc)
    in
    let cross_name =
      let doc = "The cross compiler name / toolchain name" in
      Arg.(
        required & pos 4 (some string) None & info [] ~docv:"CROSS_NAME" ~doc)
    in
    let listed_packages =
      let doc = "packages to resolve" in
      Arg.(value & pos_right 4 string [] & info [] ~doc)
    in
    Term.(
      const map_package_roots $ setup_log $ source_repository_name
      $ overlay_repository_name $ cross_template_repository_path
      $ destination_repository_path $ cross_name $ listed_packages)
  in
  let map_base_packages_t =
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
      let doc = "destination repository path" in
      Arg.(
        required
        & pos 2 (some string) None
        & info [] ~docv:"DESTINATION_REPOSITORY_PATH" ~doc)
    in
    let cross_name =
      let doc = "The cross compiler name / toolchain name" in
      Arg.(
        required & pos 3 (some string) None & info [] ~docv:"CROSS_NAME" ~doc)
    in
    Term.(
      const map_base_packages $ setup_log $ source_repository_name
      $ overlay_repository_name $ destination_repository_path $ cross_name)
  in
  let map_packages_cmd =
    let doc =
      "update a filesystem opam repository with -cross-<cross_name> packages \
       and their dependencies, ready to install with opam"
    in
    let man = [] in
    let info = Cmd.info "map-packages" ~version:"%%VERSION%%" ~doc ~man in
    Cmd.v info map_packages_t
  in
  let map_base_packages_cmd =
    let doc =
      "generate the base-* packages in an opam cross-compilation repository"
    in
    let man = [] in
    let info = Cmd.info "map-base-packages" ~version:"%%VERSION%%" ~doc ~man in
    Cmd.v info map_base_packages_t
  in

  let info =
    let doc = "opam cross compilation package management utilities" in
    let man = [] in
    Cmd.info "packman" ~version:"%%VERSION%%" ~doc ~man
  in

  let g =
    Cmdliner.Cmd.group info @@ [ map_packages_cmd; map_base_packages_cmd ]
  in
  exit (Cmd.eval g)

let () = main ()
