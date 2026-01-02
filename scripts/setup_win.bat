@echo off

for /f "tokens=*" %%g in ('odin root') do (SET ODIN_PATH=%%g)

echo Copying raylib.dll from odin/vendor/raylib to current directory for hot reload
copy "%ODIN_PATH%\vendor\raylib\windows\raylib.dll" .
