@REM x64 backend for faster compile time
rm .\asterisk_debug.exe
jai .\first.jai -x64 && .\asterisk_debug.exe .\src\draw.jai .\src\editor.jai