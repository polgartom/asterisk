@echo off

@REM x64 backend for faster compile time
del .\build\*.exe .\build\*.pdb > NUL 2> NUL

jai .\first.jai -x64 -natvis