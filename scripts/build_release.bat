@echo off

pushd %~dp0

    mkdir build

    call odin run ../src -vet -strict-style -out:../build/raytracing.exe -o:none -debug -define:IS_DEBUG=true
    rem call odin build ./src -vet -strict-style -out:./build/raytracing.exe -o:none -debug -define:IS_DEBUG=true

popd