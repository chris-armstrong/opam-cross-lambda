# opam-cross-lambda

This repository contains a number of things used to cross-compile OCaml code to Amazon Linux 2023 (AL2023), primarily for use on AWS Lambda (but not exclusively). zig is used as the cross-compile "system" as a simpler substitute for a gnu-based cross-compiler toolchain.

There are four main parts, described more in detail below:

* `opam-cross-lambda` opam repository
* `packman` - a utility for transforming regular opam packages into cross-compile packages for an opam overlay
* `cross-template-packages` - package "templates" for use with packman for packages that cannot be transformed automatically
* `validations` - a set of tests to validate specific cross-compile packages

## Compatibility

There are two cross-compile "toolchains":

* `x86_64-al2023`: Amazon Linux 2023 - x86_64
* `aarch64-al2023`: Amazon Linux 2023 - aarch64 (i.e. Gravitron)

The following cross-compile hosts and targets have been (loosely) tested and are validated in CI/CD (Github Actions):

| Host                   | Target                  | Purpose                             |
| -----------------------|-------------------------|-------------------------------------|
| x86_64-linux-gnu       | x86_64-linux-gnu        | (different glibc versions)          |
| x86_64-linux-gnu       | aarch64-linux-gnu       | compile for Gravitron instances     |
| x86_64-cygwin-gnu      | x86_64-linux-gnu        | compile for x86-64 Lambda on Windows|
| x86_64-cygwin-gnu      | aarch64-linux-gnu       | compile for Gravitron instances on Windows |
| aarch64-apple-darwin23.6.0      | x86_64-linux-gnu        | compile for x86-64 Lambda on Mac|
| aarch64-apple-darwin23.6.0      | aarch64-linux-gnu       | compile for Gravitron instances on Mac |

Other combinations may well work but they haven't been validated (nor are they in the scope of this project to validate).

## opam-cross-lambda: an opam overlay for cross-compiling to Amazon Linux targets
### Prerequisites

1. *zig*: [download a binary version of zig](https://ziglang.org/download/) and extract to your system somewhere
2. *opam*: ensure you have [installed opam for your system](https://opam.ocaml.org/doc/Install.html)
3. *opam switch*: ensure you have an opam switch created with OCaml version 5.3.0
    a. *windows* host - use the defaults and create a *Cygwin-based* switch 
    b. *linux* host - use the defaults e.g. `opam switch create default-5.3.0 --packages=ocaml.5.3.0`

## Usage

You need to specify these environment variables that determine the target environment:

* `PATH` must contain the `zig` binary (the absolute path will be saved and used configure the cross-compiler, so ensure it doesn't move. This means it doesn't require you to keep zig in your PATH for the zig compiler to continue working)

1. Add this repository as an overlay to your opam repositories
    
    ```bash
    opam repo add cross-lambda https://github.com/chris-armstrong/opam-cross-lambda.git
    ```
2. Install the cross compiler, specifying the two environment variables on the command line (they are consumed by  `conf-zig-wrapper-*`, which sets up wrappers for the zig cross-compiler) 

    ```bash
    opam install ocaml-x86_64_al2023 -y
    ```

    (if the above breaks down, try running with `--verbose` for more output from the compilation process)

### Structure of the overlay repository

* Ported packages are usually taken straight from the [main opam repository] with these changes:
    - the package directory is renamed from `<name>/<name>.<version>` to `<name>-<toolchain>/<name>-<toolchain>.<version>`
    - the `dune build` command is changed such that the `name` macro is replaced with the the package name
      explicitly, and `"-x" "<toolchain>"` is added to the command line
    - the dependencies are updated to depend on their `-<toolchain>` version if they are a *target* dependency i.e. they are not used in the build process
* Unlike other cross-compile repositories (e.g. `opam-cross-windows`), not every package is added to the overlay (typically only the compiler tools). This is because the `packman` tool (described in the next section) is the preferred method for getting cross-compile opam packages.

## packman: a tool for transforming opam packages into cross-compile packages

Once you have registered the overlay repository above and install the OCaml corss-compiler, you can create your own overlay repository with the packages you need for your target application and install them in your switch.

### What packages can be transformed
`packman` can transform most packages in the opam repository that use `dune` or `topkg` as their build system. 

The primary exceptions are:
* `conf-*` packages - these look for native dependencies in the *host* system, but we need them to present native dependencies compiled for the *target*
* anything non-dune based
* any other packages that primarily present native code - unless these are compiled entirely with `dune` (i.e. there is no other build systems involved), they most likely will not work

For any of the exceptions above, there are two options:
1. add a template to the cross-template-packages directory that is designed to work with `packman` to be transformed for any target toolchain (preferred)
2. create a new package in theh overlay repository for your particular toolchain target

### Using packman

```bash
packman map-packages \
    <source_repository_name> \
    <overlay_repository_name> \
    <cross_template_packages_path> \
    <destination_overlay_repository_path> \
    <toolchain> \
    [package name 1] [package name 2] ...

```

where:
* `source_repository_name` is the name of the opam repository you want to transform packages from (usually `default`)
* `overlay_repository_name` is the name of the overlay repository as your registered it above (e.g. `cross-lambda`)
* `cross_template_packages_path` is the path to the `cross-template-packages` directory in this repository 
* `destination_overlay_repository_path` is the path to where you want to write your overlay packages (if you have existing packages in this directory that are resolved, they will be overwritten in this directory!)
* `toolchain` is the name of the toolchain you are targeting from the overlay repository `e.g. `x86_64-al2023` or `aarch64-al2023`
* `package name 1`, `package name 2`, ... are the names of the packages you want to transform. 

You can run map-packages multiple times with different packages - if any of the same packages exist in the destination path, they will simply be rewritten again.

Once you've written the packages you want to the destination overlay directory, use `opam repo add` to add or update the destination overlay repository e.g.:

```bash
opam repo add my-cross-lambda-overlay /path/to/destination_overlay_repository_path
```


Then you can install the packages in your switch as normal e.g.:

```bash
opam install yojson-x86_64_al2023 xmlm-x86_64_al2023
```

NOTE: You will need to re-run opam repo add each time you make changes to your destination path. If you have version-controlled your destination repository (e.g. with git), you will need to commit your changes before running `opam repo add` again (uncommitted changes are ignored).

### How does package resolution work?
`map-packages` will resolve each of the packages you specify and their transitive dependencies and transform them into the destination overlay repository directory you specify. 

`packman` will first check the overlay repository for the ocaml cross-compiler toolchain (as this will be needed in resolution). For each resolved package, it will first look at the template directory for a template package and use that if it matches on the package name and version. 

Otherwise, it will look for the package in the source repository and transform it into a cross-compile package as best as it can.

Dependencies that are marked as `{build}` or `{with-test}` or `{with-doc}` will not be transformed (as they are not needed by the target). `dune`, `dune-configurator`, `ocamlfind` and other known build tools are also excluded (see `packman.ml` for the full list).


### Creating a new template package

You can create a new template package by simply:
1. Copying its definition from the source repository (don't rename it, as this will be done when applied to a particular toolchain)
2. Update the build and install scripts as needed, and/or add any patches you need. Use `%{toolchain}%` in any places you need the toolchain name (e.g. to specify the install directory or as the `-x` parameter to `dune`).

## Why was this developed?

I was interested in building a cross-compiler for Linux targeting specific GLibc versions for building code to run on AWS Lambda. AWS Lambda uses a specific Amazon Linux version running on x86_64-linux, which can be difficult to target even with an x86_64-linux distribution, simply because of glibc version incompatibilities.

Furthermore, you may be building on Windows or MacOS X; in both scenarios you need a cross-compiler. On Linux you still need a cross-compiler because you are targeting a different glibc version and possibly a different CPU architecture.

Setting up a cross-compile environment is time-consuming and difficult (obtaining the right sources, getting older versions of glibc, gcc, binutils, etc. to compile). [zig's cross-compilation facilities for C](https://zig.guide/build-system/cross-compilation/) can make much of this process unnecessary, simplifying it considerably.

## Licensing

* The packman utility (`packman` directory) is licensed under the GNU General Public License v3.0 (GPL-3.0)
* All the overlay package definitions (`packages` directory) are licensed as per their original source code license and that of the opam repository itself
* Any of the package definitions appearing under `cross-template-packages` are derived from the `opam` repository and are licensed under the same license as their original package, including all additional patches, build scripts and utility files provided
## Thanks

* ziglang for such an awesome suite of tools for C cross-compilation
* [ocaml nix overlay](https://github.com/nix-ocaml/nix-overlays/tree/master/ocaml) for the patches and instructions to get OCaml to cross-compile reliably
* `opam-cross-windows` as a handy reference for hard-to-port packages
