#!/usr/bin/env bash
# set -e

ARGS="-define:RAYLIB_SHARED=true"
ARGS+=" -show-timings"
# ARGS+=" -no-bounds-check"
# ARGS+=" -ignore-vs-search"
ARGS+=" -o:speed"
ARGS+=" -debug"

odin build ./src -build-mode:dll -out:./build/game.so $ARGS