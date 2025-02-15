# opam-cross-generic

An opam overlay repository that demonstrates the use of the [zig](https://ziglang.org/) compiler to cross-compile OCaml between different platforms.

## What is tested?

The repository contains an OCaml cross-compiler package (`ocaml-cross`; OCaml 5.2.0).

There are two cross-compile systems:

* `-cross-x86_64-al2023`: Amazon Linux 2023 - x86_64
* `-cross-aarch64-al2023`: Amazon Linux 2023 - aarch64 (i.e. Gravitron)

The following cross-compile hosts and targets have been (loosely) tested:

| Host                   | Target                  | Purpose                             |
| -----------------------|-------------------------|-------------------------------------|
| x86_64-linux-gnu       | x86_64-linux-gnu        | (different glibc versions)          |
| x86_64-linux-gnu       | aarch64-linux-gnu       | compile for Gravitron instances     |
| x86_64-cygwin-gnu      | x86_64-linux-gnu        | compile for x86-64 Lambda on Windows|
| x86_64-cygwin-gnu      | aarch64-linux-gnu       | compile for Gravitron instances on Windows |

Other combinations may well work but they haven't been validated.

## Prerequisites

1. *zig*: [download a binary version of zig](https://ziglang.org/download/) and extract to your system somewhere
2. *opam*: ensure you have [installed opam for your system](https://opam.ocaml.org/doc/Install.html)
3. *opam switch*: ensure you have an opam switch created with OCaml version 5.2.0
    a. *windows* host - use the defaults and create a *Cygwin-based* switch 
    b. *linux* host - use the defaults e.g. `opam switch create default-5.2.0 --packages=ocaml.5.2.0`

## Usage

You need to specify these environment variables that determine the target environment:

* `ZIG_PATH` is the absolute path to the ZIG binary e.g. `ZIG_PATH=/opt/zig-linux-x86_64-0.14.0-dev.363+c3faae6bf/zig`

1. Add this repository as an overlay to your opam repositories
    
    ```bash
    opam repo add cross https://github.com/chris-armstrong/opam-cross-generic.git
    ```
2. Install the cross compiler, specifying the two environment variables on the command line (they are consumed by `conf-ocaml-cross` and `conf-zig-wrapper`, which sets up wrappers for the zig cross-compiler and ensures that the correct flags are used to build the OCaml cross-compiler) 

    ```bash
    ZIG_PATH=/opt/zig-linux-x86_64-0.14.0-dev.363+c3faae6bf/zig opam install ocaml-cross-x86_64-al2023 -y
    ```

    (if the above breaks down, try running with `--verbose` for more output from the compilation process)

3. Try running one of the examples in this repository e.g. targeting aarch64-linux-gnu:

    ```bash
    git clone https://github.com/chris-armstrong/opam-cross-generic.git
    cd opam-cross-generic/validations/test-fmt
    opam install fmt-cross -y
    dune build -x cross
    # binaries are built into _build/default.cross/
    # you need to install `qemu-system-arm` and `qemu-user` on Ubuntu to run aarch64 binaries directly
    qemu-aarch64 -L /usr/aarch64-linux-gnu _build/default.cross/test_fmt.exe
    ```

## Structure of the repository

* `conf-ocaml-cross` sets up the configuration for the cross-compiler
* `conf-zig-wrapper` creates wrapper scripts for the zig compiler with the `target` triple embedded
* `ocaml-cross` is the cross compiler
* Ported packages are usually taken straight from the [main opam repository] with these changes:
    - the package directory is renamed from `<name>/<name>.<version>` to `<name>-cross/<name>-cross.<version>`
    - the `dune build` command is changed such that the `name` macro is replaced with the the package name
      explicitly, and `"-x" "cross"` is added to the command line
    - the dependencies are updated to depend on their `-cross` version if they are a *target* dependency i.e. they are not used in the build process

## Why was this developed?

I was interested in building a cross-compiler for Linux targeting specific GLibc versions for building code to run on AWS Lambda. AWS Lambda uses a specific Amazon Linux version running on x86_64-linux, which can be difficult to target even with an x86_64-linux distribution, simply because of glibc version incompatibilities.

Furthermore, you may be building on Windows or MacOS X; in both scenarios you need a cross-compiler.

Setting up a cross-compile environment is time-consuming and difficult (obtaining the right sources, getting older versions of glibc, gcc, binutils, etc. to compile). [zig's cross-compilation facilities for C](https://zig.guide/build-system/cross-compilation/) can make much of this process unnecessary, simplifying it considerably.

## Future work

* Get other interesting packages ported
* Find a generic way to create the `-cross` packages
* Work out how to get packages with `C` dependencies to cross-compile correctly
* MacOS X host support

## Thanks

* ziglang for such an awesome suite of tools for C cross-compilation
* [ocaml nix overlay](https://github.com/nix-ocaml/nix-overlays/tree/master/ocaml) for the patches and instructions to get OCaml to cross-compile reliably
