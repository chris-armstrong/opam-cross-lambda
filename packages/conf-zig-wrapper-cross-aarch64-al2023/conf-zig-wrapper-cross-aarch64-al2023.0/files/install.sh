#!/bin/bash

PREFIX=$1
HOST_TARGET=$2
ZIG=$(which zig)

if [ -z "${ZIG}" ]
then
  echo "Zig not found in path!"
  exit 1
fi

case "$(uname -s)" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGW;;
    MSYS_NT*)   machine=MSys;;
    *)          machine="UNKNOWN:${unameOut}"
esac

# Make a shell wrapper for $2 that passes its arguments appended
# to the end, stored in $1
function make_wrapper() {
  wrapper_script_path=$1
  caml_bin=$2
  cat << EOF > "$wrapper_script_path"
#!/bin/bash

NEW_ARGS=""

for ARG in "\$@"; do NEW_ARGS="\$NEW_ARGS \"\$ARG\""; done
eval "${caml_bin} \$NEW_ARGS"
EOF
  chmod u+x "$wrapper_script_path"
}

# Make a `.cmd` wrapper that can be called from ocamlmklib
# using the standard windows cmd.exe shell (using Unix.command)
function make_windows_cmd_wrapper() {
  if [[ "$machine" == "Cygwin" ]]
  then
    wrapper_script_path=$1
    cmd_script_path=$(dirname "$1")/$(basename "$1").cmd
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
# -- target C compiler wrapper scripts (these need to be added to the prefix straight away)
mkdir -p "${PREFIX}/bin"

zig_cc_wrapper="${PREFIX}/bin/$HOST_TARGET-target-cc"
make_wrapper "$zig_cc_wrapper" "${ZIG} cc -target ${HOST_TARGET}"
make_windows_cmd_wrapper "$zig_cc_wrapper"

zig_aspp_wrapper="${PREFIX}/bin/$HOST_TARGET-target-aspp"
make_wrapper "$zig_aspp_wrapper" "${ZIG} cc -target ${HOST_TARGET} -c"
make_windows_cmd_wrapper "$zig_aspp_wrapper"

zig_ar_wrapper="${PREFIX}/bin/$HOST_TARGET-target-ar"
make_wrapper "$zig_ar_wrapper" "${ZIG} ar"
make_windows_cmd_wrapper "$zig_ar_wrapper"

zig_ar_wrapper="${PREFIX}/bin/$HOST_TARGET-target-ranlib"
make_wrapper "$zig_ar_wrapper" "${ZIG} ranlib -target ${HOST_TARGET}"
make_windows_cmd_wrapper "$zig_ar_wrapper"
