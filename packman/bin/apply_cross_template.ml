open Containers

let has_template ~cross_template_repository_path package =
  let repository_root =
    OpamFilename.Dir.of_string cross_template_repository_path
  in
  let package_name = OpamPackage.name_to_string package in
  let template_path =
    OpamRepositoryPath.opam repository_root (Some package_name) package
  in
  OpamFile.exists template_path

let apply_cross_template ~cross_template_repository_path
    ~destination_repository_path ~cross_name ~toolchain package =
  let repository_root =
    OpamFilename.Dir.of_string cross_template_repository_path
  in
  let package_name = OpamPackage.name_to_string package in
  let template_path =
    OpamRepositoryPath.opam repository_root (Some package_name) package
  in
  let destination_package_name = package_name ^ "-cross-" ^ cross_name in
  let destination_package =
    OpamPackage.create
      (OpamPackage.Name.of_string destination_package_name)
      (OpamPackage.version package)
  in
  let destination_path =
    OpamRepositoryPath.opam
      (OpamFilename.Dir.of_string destination_repository_path)
      (Some destination_package_name) destination_package
  in
  OpamFile.OPAM.read template_path
  |> OpamFile.OPAM.to_string_with_preserved_format template_path
  |> String.replace ~sub:"%{cross_name}%" ~by:cross_name
  |> String.replace ~sub:"%{toolchain}%" ~by:toolchain
  |> OpamFile.OPAM.read_from_string ~filename:destination_path
  |> OpamFile.OPAM.write destination_path
