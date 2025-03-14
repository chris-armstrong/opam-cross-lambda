open Containers

type t = { cross_name : string }

let name x = x.cross_name
let toolchain x = String.sub ~sub:"-" ~by:"_" x.cross_name

let package_name cross package =
  OpamPackage.name_to_string package ^ "-cross-" ^ cross.cross_name

