@echo off

del .\build\asterisk.exe .\build\asterisk.pdb > NUL 2> NUL

jai .\build.jai - release bake_font