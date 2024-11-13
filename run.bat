@echo off

del .\asterisk_debug.exe .\asterisk_debug.pdb > NUL 2> NUL

@REM Using x64 backend due faster compile time
jai .\first.jai -x64 && .\asterisk_debug.exe .\src\draw.jai .\src\editor.jai