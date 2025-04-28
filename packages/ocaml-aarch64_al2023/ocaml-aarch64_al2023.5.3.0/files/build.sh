#!/bin/sh

set -eux

# determine runtime machine
unameOut=$(uname -s)
case "$unameOut" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGW;;
    MSYS_NT*)   machine=MSys;;
    *)          machine="UNKNOWN:${unameOut}"
esac

PREFIX=
CPU_COUNT=4
SOURCE_DIR=$(realpath "${PWD}")
HOST_SWITCH=
ZIG=zig
EXTRA_CONFIG_OPTS=
OCAML_VERSION=5.2
FLEXDLL_PATH=

usage () { echo "$0 -p <prefix> -o <host_switch> -c <cross_name> -t <ocaml_target> [-j <cpu count>] [-s <sources_dir>] [-z <path_to_zig_executable>] [-a <extra-config-opts>] -f <flexdll_path> -v <ocaml_version>"; exit 1; }

while getopts ":hp:t:j:s:z:g:o:a:v:t:f:c:" option; do
  case $option in
    p)
      PREFIX=${OPTARG}
      [ "$machine" = "Cygwin" ] && PREFIX=$(cygpath "$PREFIX")
      ;;
    j)
      CPU_COUNT=${OPTARG}
      ;;
    s)
      SOURCE_DIR=${OPTARG}
      [ "$machine" = "Cygwin" ] && SOURCE_DIR=$(cygpath "$SOURCE_DIR")
      ;;
    z)
      ZIG=${OPTARG}
      ;;
    v)
      OCAML_VERSION=${OPTARG}
      ;;
    c)
      CROSS_NAME=${OPTARG}
      ;;
    t)
      OCAML_TARGET=${OPTARG}
      ;;
    o)
      HOST_SWITCH=${OPTARG}
      [ "$machine" = "Cygwin" ] && HOST_SWITCH=$(cygpath "$HOST_SWITCH")
      ;;
    a)
      EXTRA_CONFIG_OPTS=${OPTARG}
      ;;
    f)
      FLEXDLL_PATH=${OPTARG}
      ;;
    h | *)
      usage
    ;;
  esac
done

echo "Build plan"
echo "----------"
echo ""
echo "Prefix: ${PREFIX}"
echo "Cores: ${CPU_COUNT}"
echo "Cross Name: ${CROSS_NAME}"
echo "OCaml Target: ${OCAML_TARGET}"
echo "Zig Compiler: ${ZIG}"
echo "Host Switch: ${HOST_SWITCH}"
echo "Sources Dir: ${SOURCE_DIR}"
echo "OCaml Version: ${OCAML_VERSION}"
echo "Flexdll path: ${FLEXDLL_PATH}"

if [ -z "${PREFIX}" ]
then
  echo "Prefix directory not specified"
  exit 1
fi

if ! which -s "$ZIG" > /dev/null
then
  echo "Zig binary not executable"
  exit 1
fi

if [ ! -d "${SOURCE_DIR}"  ]
then
  echo "Sources directory not found."
  exit 1
fi

if [ ! -d "${HOST_SWITCH}" ]
then
  echo "Host switch directory not found"
  exit 1
fi

if [ ! -x "${HOST_SWITCH}/bin/ocamlc.opt" ] || [ ! -x "${HOST_SWITCH}/bin/ocamlopt.opt" ]
then
  echo "Host compiler not found"
  exit 1
fi

# OCaml is built in its source directory
BUILD_ROOT="${SOURCE_DIR}"

# Configuration of host switch
HOST_MAKEFILE_CONFIG="$HOST_SWITCH/lib/ocaml/Makefile.config"

# make_wrapper <script_path> <binary_to_wrap>
# Make a shell wrapper for $2 that passes its arguments appended
# to the end, stored in $1
make_wrapper() {
  wrapper_script_path=$1
  caml_bin=$2
  cat << EOF > "$wrapper_script_path"
#!/bin/bash

NEW_ARGS=""

for ARG in "\$@"; do NEW_ARGS="\$NEW_ARGS '\$ARG'"; done
eval "${caml_bin} \$NEW_ARGS"
EOF
  chmod +x "$wrapper_script_path"
}

# make_windows_cmd_wrapper <script_path>
#
# Make a `.cmd` wrapper that can be called from ocamlmklib
# using the standard windows cmd.exe shell (using Unix.command)
# to run the specified script in Cygwin bash
make_windows_cmd_wrapper() {
  if [ "$machine" = "Cygwin" ]
  then
    wrapper_script_path=$1
    cmd_script_path="$(dirname "$1")/$(basename "$1").cmd"
    cat << EOF > "$cmd_script_path"
@echo off
setlocal
 
if not exist "%~dpn0" echo Script "%~dpn0" not found & exit 2
 
set _CYGBIN=$(cygpath -w /)\\bin\\
if not exist "%_CYGBIN%" echo Couldn't find Cygwin at "%_CYGBIN%" & exit 3
 
:: Resolve ___.sh to /cygdrive based *nix path and store in %_CYGSCRIPT
for /f "delims=" %%A in ('%_CYGBIN%cygpath.exe "%~dpn0"') do set _CYGSCRIPT=%%A
 
:: Throw away temporary env vars and invoke script, passing any args that were passed to us
endlocal & %_CYGBIN%bash "%_CYGSCRIPT%" %*
EOF
  fi
}

# trim <string>
#
# trim the specified string of leading and trailing whitespace
trim() {
  echo "$1" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# get_host_variable <variable_name>
# 
# get a variable from variable from the Makefile.config of the host switch
get_host_variable () {
  grep "^$1=" "$HOST_MAKEFILE_CONFIG" | awk -F '=' '{print $2}'
}

# get_host_ocamlc_variable <variable_name>
# 
# retrieve variable from `ocamlc -config` of host switch
get_host_ocamlc_variable () {
  trim "$("$HOST_SWITCH/bin/ocamlc" -config | grep "^$1:" | cut -d ':' -f 2)"
}

# ###############################
# Create OCaml and Compiler wrapper scripts (assists with multi-arg changes)

# -- host compiler wrapper scripts (anchored in the build root)
host_compiler_path="$BUILD_ROOT/host-bin"
mkdir -p "$host_compiler_path"

# Get the native path (in Windows terms) of the host switch
host_switch_native="$HOST_SWITCH"
[ "$machine" = "Cygwin" ] && host_switch_native=$(cygpath -m "$host_switch_native")

host_ocamlc_wrapper="$host_compiler_path/host-ocamlc"
if [ "$machine" = "Cygwin" ] || [ "$machine" = "MinGW" ]
then
  make_wrapper "$host_ocamlc_wrapper" "$host_switch_native/bin/ocamlc.opt -I ${host_switch_native}/lib/ocaml -I $host_switch_native/lib/ocaml/flexdll -I ${host_switch_native}/lib/ocaml/stublibs -I +unix -nostdlib "
else
  make_wrapper "$host_ocamlc_wrapper" "$host_switch_native/bin/ocamlc.opt -I ${host_switch_native}/lib/ocaml -I ${host_switch_native}/lib/ocaml/stublibs -I +unix -nostdlib "
fi
make_windows_cmd_wrapper "$host_ocamlc_wrapper"

host_ocamlopt_wrapper="$host_compiler_path/host-ocamlopt"
if [ "$machine" = "Cygwin" ] || [ "$machine" = "MinGW" ]
then
  make_wrapper "$host_ocamlopt_wrapper" "${host_switch_native}/bin/ocamlopt.opt -I ${host_switch_native}/lib/ocaml -I $host_switch_native/lib/ocaml/flexdll -I +unix -nostdlib "
else
  make_wrapper "$host_ocamlopt_wrapper" "${host_switch_native}/bin/ocamlopt.opt -I ${host_switch_native}/lib/ocaml -I +unix -nostdlib "
fi
make_windows_cmd_wrapper "$host_ocamlopt_wrapper"

# Anchor the BUILD_ROOT with a native (windows) path that works outside cygwin
build_root_native=$BUILD_ROOT
[ "$machine" = "Cygwin" ] && build_root_native=$(cygpath -m "$BUILD_ROOT")

# -- target ocaml compiler wrapper scripts (stored in temporary directory)
target_ocamlc_wrapper=$(mktemp -t target-ocamlc-XXXXX)
make_wrapper "$target_ocamlc_wrapper" "$build_root_native/ocamlc.opt -I $build_root_native/stdlib -I $build_root_native/otherlibs/unix -I ${host_switch_native}/lib/ocaml/stublibs -nostdlib " # trailing space is important
make_windows_cmd_wrapper "$target_ocamlc_wrapper"

target_ocamlopt_wrapper=$(mktemp -t target-ocamlopt-XXXXX)
make_wrapper "$target_ocamlopt_wrapper" "$build_root_native/ocamlopt.opt -I $build_root_native/stdlib -I $build_root_native/otherlibs/unix -nostdlib " # trailing space is important
make_windows_cmd_wrapper "$target_ocamlopt_wrapper"

# Disable function sections if the build machine doesn't support it
if [ "$(get_host_ocamlc_variable "function_sections")" != "true" ]
then
  EXTRA_CONFIG_OPTS="${EXTRA_CONFIG_OPTS} --disable-function-sections"
  echo "--- function sections disabled on host, disabling for target"
fi

if [ $(expr "$OCAML_TARGET" : "^x86_64-w64-") -gt 0 ]
then
  echo "--- x86_64-w64-* target means we need flexdll"
  EXTRA_CONFIG_OPTS="${EXTRA_CONFIG_OPTS} --with-flexdll=${FLEXDLL_PATH}"
else
  EXTRA_CONFIG_OPTS="${EXTRA_CONFIG_OPTS} --disable-flexdll"
fi

echo "--- transposing host compiler configuration"

echo "======= > ocamlc -config"
"$HOST_SWITCH/bin/ocamlc" -config
echo "======= > Makefile.config"
cat "$HOST_MAKEFILE_CONFIG"
echo "======="

host_cc=$(get_host_variable "CC")
host_cflags=$(get_host_variable "CFLAGS")
host_c_libraries=$(get_host_variable "LDFLAGS")
host_cppflags=$(get_host_variable "CPPFLAGS")
windows_unicode="$(get_host_ocamlc_variable "windows_unicode")"

echo "--- host_cc=${host_cc}"
echo "--- host_cflags=${host_cflags}"
echo "--- host_c_libraries=${host_c_libraries}"
echo "--- host_cppflags=${host_cppflags}"
echo "--- windows_unicode='${windows_unicode}'"

echo "--- Clean all configuration and previous builds"
cd "${BUILD_ROOT}"
rm -f config.cache
make distclean

# bootstrap
echo "--- Build bootstrap (build -> host) compiler"
prefix_native="$PREFIX"
[ "$machine" = "Cygwin" ] && prefix_native=$(cygpath -m "$PREFIX")
ln_use="ln -s "
[ "$machine" = "Cygwin" ] && ln_use="cp "
echo "configuring with --host=${OCAML_TARGET} --prefix=${prefix_native} ${EXTRA_CONFIG_OPTS}"
export "PATH=$PREFIX/bin:$PATH"
# FIXME: patch configure to ignore flexlink when the host triplet is not Cygwin/MingW 
zig_native="$ZIG"
[ "$machine" = "Cygwin" ] && zig_native=$(cygpath -m "$ZIG")
./configure --host="${OCAML_TARGET}" --prefix="$prefix_native" --disable-ocamldoc --disable-stdlib-manpages --disable-ocamltest --disable-ocamldebug \
  ${EXTRA_CONFIG_OPTS} \
  -C "CC=${CROSS_NAME}-target-cc" \
  "AR=${CROSS_NAME}-target-ar" \
  "RANLIB=${CROSS_NAME}-target-ranlib" \
  "ASPP=${CROSS_NAME}-target-aspp" \
  "MIN64CC=${CROSS_NAME}-target-cc" \
  "PARTIALLD=${CROSS_NAME}-target-cc -r " \
  "LD=${CROSS_NAME}-target-cc" \
  "CFLAGS=-I${PREFIX}/include " \
  "LDFLAGS=-L${PREFIX}/lib " \
  "LN=${ln_use}" || { echo " --- configure failed!"; cat config.log; exit 1; }

# Set up sak compiler
cp Makefile.config Makefile.config.bak
echo "SAK_CC=${zig_native} cc" >> Makefile.config # fuck it lets just use zig because x86_64-w64-mingw32-gcc wants to be broken on Windows
# shellcheck disable=SC2016
echo 'SAK_CFLAGS=$(OC_CFLAGS) $(OC_CPPFLAGS)' >> Makefile.config
if [ "$windows_unicode" = "true" ]
then
  echo "SAK_LINK=\$(SAK_CC) -municode \$(SAK_CFLAGS) \$(OUTPUTEXE)\$(1) \$(2)" >> Makefile.config
else 
  echo "SAK_LINK=\$(SAK_CC) \$(SAK_CFLAGS) \$(OUTPUTEXE)\$(1) \$(2)" >> Makefile.config
fi
echo 'LN=cp ' >> Makefile.build_config

# Set paths to host switch
OCAMLRUN="$HOST_SWITCH/bin/ocamlrun"
OCAMLLEX="$HOST_SWITCH/bin/ocamllex"
OCAMLYACC="$HOST_SWITCH/bin/ocamlyacc"
CAMLDEP="$HOST_SWITCH/bin/ocamlc"

NATDYNLINK=$(get_host_variable "NATDYNLINK")
NATDYNLINKOPTS=$(get_host_variable "NATDYNLINKOPTS")

has_zstd="false"
if [ "$(expr "$(get_host_ocamlc_variable "bytecomp_c_libraries")" : ".*zstd" )" -gt 0 ]
then
  echo "-- zstd detected in host compiler! --"
  has_zstd="true"
else
  echo "-- zstd not detected in host compiler! -- $( "${HOST_SWITCH}/bin/ocamlopt.opt" -config | grep "^bytecomp_c_libraries:")"
fi

make_caml () {
  echo "-> make_caml $*"
  make "-j$CPU_COUNT" \
       CAMLDEP="$CAMLDEP -depend" \
       OCAMLLEX="$OCAMLLEX" \
       OCAMLYACC="$OCAMLYACC" CAMLYACC="$OCAMLYACC" \
       CAMLRUN="$OCAMLRUN" OCAMLRUN="$OCAMLRUN" \
       NEW_OCAMLRUN="$OCAMLRUN" \
       CAMLC="$CAMLC" OCAMLC="$CAMLC" \
       CAMLOPT="$CAMLOPT" OCAMLOPT="$CAMLOPT" \
       MIN64CC="$MIN64CC" \
       "$@"
}

make_host () {
  echo "--making host: $*--"
  CAMLC="$host_compiler_path/host-ocamlc"
  [ "$machine" = "Cygwin" ] && CAMLC=$(cygpath -m "$(which "$CAMLC")")
  CAMLOPT="$host_compiler_path/host-ocamlopt"
  [ "$machine" = "Cygwin" ] && CAMLOPT=$(cygpath -m "$(which "$CAMLOPT")")
  
  ZSTD_LIBS=$(get_host_variable "ZSTD_LIBS")
  BYTECC_LIBS=$(get_host_variable "BYTECC_LIBS")
  MIN64CC="${CROSS_NAME}-target-cc"
  make_caml \
    NATDYNLINK="$NATDYNLINK" \
    NATDYNLINKOPTS="$NATDYNLINKOPTS" \
    ZSTD_LIBS="${ZSTD_LIBS}" \
    BYTECC_LIBS="${BYTECC_LIBS}" \
    MIN64CC="$MIN64CC" \
    "$@"
}

make_target () {
  echo "making target: $*"
  CAMLC="${target_ocamlc_wrapper}"
  [ "$machine" = "Cygwin" ] && CAMLC=$(cygpath -m "$CAMLC")
  CAMLOPT="${target_ocamlopt_wrapper}"
  [ "$machine" = "Cygwin" ] && CAMLOPT=$(cygpath -m "$CAMLOPT")

  MIN64CC="${CROSS_NAME}-target-cc"
  make_caml \
    BUILD_ROOT="$build_root_native" \
    CAMLC="$CAMLC" \
    CAMLOPT="$CAMLOPT" \
    MIN64CC="$MIN64CC" \
    "$@"
}
echo "---- MAKING HOST ----"
make_host runtime 
make_host coreall
make_host opt-core
make_host ocamlc.opt
make_host ocamlopt.opt
make_host compilerlibs/ocamltoplevel.cma
make_host otherlibraries 
make_host ocamltoolsopt ocamltoolsopt.opt 
# make_host othertools

echo "---- MAKING TARGET ----"
rm $(find . | grep -E '\.cm.?.$')
make_target -C stdlib all allopt
make_target ocaml ocamlc
make_target ocamlopt
make_target otherlibraries otherlibrariesopt ocamltoolsopt \
            driver/main.cmx driver/optmain.cmx

# build the compiler shared libraries with the target `zstd.npic.o`
cp Makefile.config.bak Makefile.config
echo "SAK_CC=${CROSS_NAME}-target-cc" >> Makefile.config
make_target compilerlibs/ocamlcommon.cmxa \
            compilerlibs/ocamlbytecomp.cmxa \
            compilerlibs/ocamloptcomp.cmxa 
            # compilerlibs/ocamltoplevel.cmxa
if [ $(expr "$OCAML_VERSION" : '^5\.') -gt 0 ]
then
  make_target -C otherlibs all allopt
fi
