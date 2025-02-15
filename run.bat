@echo off

@REM call .\compile.bat && .\build\devbuild.exe .\..\sample.txt

set testfile=%1
IF "%testfile%" == "" (
    set testfile=..\..\.build\.added_strings_w3.jai
)

call .\compile.bat && .\build\devbuild.exe %testfile%