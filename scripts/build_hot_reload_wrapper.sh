#!/usr/bin/env bash

mkdir -p ./build

odin build ./src/hot_reload -out:./build/raytracing.bin -debug -define:IS_DEBUG=true

cp ./libraylib.so.550 ./build/libraylib.so.550