#!/bin/bash

CROSS_NAME=$1
TARGET_OS=$2
TARGET_ARCH=$3
ZIG=$(which zig)

echo "zig_path: \"${ZIG}\"" >> "conf-zig-wrapper-${CROSS_NAME}.config"
echo "target_os: \"${TARGET_OS}\"" >> "conf-zig-wrapper-${CROSS_NAME}.config"
echo "target_arch: \"${TARGET_ARCH}\"" >> "conf-zig-wrapper-${CROSS_NAME}.config"
