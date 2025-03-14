open Containers

type t = { cross_name : string }

let cross_name x = x.cross_name
let toolchain x = String.sub ~sub:"-" ~by:"_" x.cross_name

module Package = struct
  let t = { package_name : string }
  let cross_name ~cross package = package.name ^ "-cross-" ^ cross.cross_name
end
