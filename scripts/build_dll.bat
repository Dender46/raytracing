@echo off

set ARGS= -define:RAYLIB_SHARED=true
set ARGS=%ARGS% -show-timings
rem set ARGS=%ARGS% -no-bounds-check
rem set ARGS=%ARGS% -ignore-vs-search
set ARGS=%ARGS% -o:speed
set ARGS=%ARGS% -debug
odin build ../src -build-mode:dll -out:../build/game.dll %ARGS%