open Containers

type t = { cross_name : string }

let name x = x.cross_name
let of_string cross_name = { cross_name }
let to_string = name
let toolchain x = String.replace ~sub:"-" ~by:"_" x.cross_name

let map_package_name cross package_name =
  OpamPackage.Name.of_string
    (OpamPackage.Name.to_string package_name ^ "-" ^ cross.cross_name)
