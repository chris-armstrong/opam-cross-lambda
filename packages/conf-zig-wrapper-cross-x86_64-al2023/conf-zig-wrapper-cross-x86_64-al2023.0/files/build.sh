#!/bin/bash

CROSS_NAME=$1
ZIG=$(which zig)


case "$(uname -s)" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGW;;
    MSYS_NT*)   machine=MSys;;
    *)          machine="UNKNOWN:${unameOut}"
esac

( [ "$machine" = "Cygwin" ] || [ "$machine" = "MinGW" ] ) && \
  ZIG=$(cygpath -m "$ZIG")

echo "zig_path: \"${ZIG}\"" >> "conf-zig-wrapper-${CROSS_NAME}.config"
