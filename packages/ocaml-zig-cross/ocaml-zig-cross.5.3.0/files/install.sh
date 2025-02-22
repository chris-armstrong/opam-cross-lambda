#!/bin/bash

set -exu

PREFIX=$1
HOST_SWITCH=$2
CROSS_NAME=$3

export ZIG_GLOBAL_CACHE_DIR=${TMPDIR:-/tmp}/zig-cache
export ZIG_LOCAL_CACHE_DIR=${TMPDIR:-/tmp}/zig-cache-local

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

# update paths to use cygpath format
mkdir -p "$PREFIX"
[ "$machine" = "Cygwin" ] && PREFIX=$(cygpath "$PREFIX")
[ "$machine" = "Cygwin" ] && HOST_SWITCH=$(cygpath "$HOST_SWITCH")
	
if [ ! -d "${PREFIX}" ]
then
    echo "Prefix directory \"$PREFIX\" is not a directory / does not exist"
	exit 1
fi

if [ ! -d "${HOST_SWITCH}" ]
then
    echo "Host switch directory \"$HOST_SWITCH\" does not exist"
	exit 1
fi

if [ -z "$CROSS_NAME" ]
then
	echo "A toolchain name must be specified"
	exit 1
fi

echo "-- making directories in $PREFIX"
mkdir -p "$PREFIX/bin"
mkdir -p "$PREFIX/lib"
mkdir -p "$PREFIX/lib/ocaml/caml"
mkdir -p "$PREFIX/lib/ocaml/stublibs"
mkdir -p "$PREFIX/lib/stublibs"

echo "-- installing compiler tooling to $PREFIX"
OCAMLRUN="$HOST_SWITCH/bin/ocamlrun" make install

echo "-- seting up ocamlfind config for host switch $HOST_SWITCH with toolchain $CROSS_NAME"
mv "$HOST_SWITCH/lib/findlib.conf" "$HOST_SWITCH/lib/findlib.conf.bak"
sed -e "/(${CROSS_NAME})/d" "$HOST_SWITCH/lib/findlib.conf.bak" > "$HOST_SWITCH/lib/findlib.conf"
prefix_native="${PREFIX}"
[ "$machine" = "Cygwin" ] && prefix_native=$(cygpath -m "$prefix_native")
cat << EOF >> "$HOST_SWITCH/lib/findlib.conf"
path($CROSS_NAME)="$prefix_native/lib:$PREFIX/lib/ocaml"
destdir($CROSS_NAME)="$prefix_native/lib"
stdlib($CROSS_NAME)="$prefix_native/lib/ocaml"
ocamlc($CROSS_NAME)="$prefix_native/bin/ocamlc"
ocamlopt($CROSS_NAME)="$prefix_native/bin/ocamlopt"
ocamldep($CROSS_NAME)="$prefix_native/bin/ocamldep"
ocamlmklib($CROSS_NAME)="$prefix_native/bin/ocamlmklib"
ldconf($CROSS_NAME)="$prefix_native/lib/ocaml/ld.conf"
EOF

cat << EOF > "$PREFIX/lib/ocaml/ld.conf"
$prefix_native/lib/ocaml/stublibs
$prefix_native/lib/ocaml
EOF
