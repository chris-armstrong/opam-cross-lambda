open Containers

module Logs =
  (val Logs.src_log
         (Logs.Src.create ~doc:"packman converting opam files from a template"
            "Packman.apply_cross_template"))

let has_template ~cross_template_repository_path package =
  let repository_root =
    OpamFilename.Dir.of_string cross_template_repository_path
  in
  let package_name = OpamPackage.name_to_string package in
  let template_path =
    OpamRepositoryPath.opam repository_root (Some package_name) package
  in
  Logs.info (fun m ->
      m "has_template: checking for template at %s"
        (template_path |> OpamFile.to_string));
  OpamFile.exists template_path

let copy_file source_path destination_path =
  (* Open the source file for reading *)
  let destination_dir = FilePath.dirname destination_path in
  if not (String.equal destination_dir "") then
    (* Create the destination directory if it doesn't exist *)
    FileUtil.mkdir ~parent:true destination_dir;
  FileUtil.cp [ source_path ] destination_path

let apply_cross_template ~cross_template_repository_path
    ~destination_repository_path ~cross package =
  let repository_root =
    OpamFilename.Dir.of_string cross_template_repository_path
  in
  let package_name = OpamPackage.name_to_string package in
  let template_path =
    OpamRepositoryPath.opam repository_root (Some package_name) package
  in
  let cross_name = Cross.to_string cross in
  let destination_package_name =
    Cross.map_package_name cross (OpamPackage.name package)
  in
  let destination_package =
    OpamPackage.create destination_package_name (OpamPackage.version package)
  in
  let destination_path =
    OpamRepositoryPath.opam destination_repository_path
      (Some (destination_package_name |> OpamPackage.Name.to_string))
      destination_package
  in
  let source_package_path =
    OpamRepositoryPath.packages repository_root (Some package_name) package
  in
  let destination_package_path =
    OpamRepositoryPath.packages destination_repository_path
      (Some (destination_package_name |> OpamPackage.Name.to_string))
      destination_package
  in
  try
    Ok
      (let opam_source = OpamFile.OPAM.read template_path in
       let extra_files = OpamFile.OPAM.extra_files opam_source in
       let destination_string =
         template_path |> OpamFile.to_string |> In_channel.open_bin
         |> IO.read_all
         |> String.replace ~sub:"%{cross_name}%" ~by:cross_name
         |> String.replace ~sub:"%{toolchain}%" ~by:cross_name
       in
       Logs.debug (fun m -> m "apply_cross_template: %s" destination_string);
       Out_channel.with_open_bin (destination_path |> OpamFile.to_string)
         (fun oc -> IO.write_line oc destination_string);
       Option.iter
         (fun extra_files ->
           List.iter
             (fun (source_file, _) ->
               let source_file = source_file |> OpamFilename.Base.to_string in
               let source_path =
                 OpamFilename.Op.(source_package_path / "files" // source_file)
                 |> OpamFilename.to_string
               in
               let destination_path =
                 OpamFilename.Op.(
                   destination_package_path / "files" // source_file)
                 |> OpamFilename.to_string
               in
               copy_file source_path destination_path)
             extra_files)
         extra_files)
  with e ->
    Logs.info (fun m -> m "exception: %s" (Printexc.to_string e));
    Error (Fmt.str "Failed to apply cross template for package %s" package_name)
