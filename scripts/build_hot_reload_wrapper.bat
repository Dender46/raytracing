@echo off

pushd %~dp0

    mkdir ..\build

    odin build ../src/hot_reload -out:../build/raytracing.exe -debug -define:IS_DEBUG=true

    copy ..\raylib.dll ..\build

popd