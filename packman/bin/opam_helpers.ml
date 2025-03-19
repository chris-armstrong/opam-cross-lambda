let map_variables str callback =
  (* Create a regex pattern for %{variable_name:package_name}% *)
  let pattern =
    Re.compile
      (Re.seq
         [
           Re.str "%{";
           Re.group (Re.rep1 (Re.alt [ Re.alnum; Re.char '_'; Re.char '-' ]));
           (* package_name *)
           Re.char ':';
           Re.group (Re.rep1 (Re.alt [ Re.alnum; Re.char '-' ]));
           (* variable_name *)
           Re.str "}%";
         ])
  in

  (* Use Re.replace for substitution with a custom function *)
  Re.replace ~all:true pattern
    ~f:(fun match_result ->
      let groups = Re.Group.all match_result in
      let variable_name = groups.(2) in
      let package_name = groups.(1) in

      (* Call the callback to get the new variable_name and package_name *)
      let new_var_name, new_pkg_name = callback (variable_name, package_name) in

      (* Return the new interpolation format *)
      Printf.sprintf "%%{%s:%s}%%" new_pkg_name new_var_name)
    str
