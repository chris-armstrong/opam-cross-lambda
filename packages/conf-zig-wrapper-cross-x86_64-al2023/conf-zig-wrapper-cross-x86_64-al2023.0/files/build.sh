#!/bin/bash

CROSS_NAME=$1
ZIG=$(which zig)

echo "zig_path: ${ZIG}" >> "conf-zig-wrapper-${CROSS_NAME}.config"
