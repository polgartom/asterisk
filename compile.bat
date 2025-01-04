@echo off

del .\build\asterisk_devbuild.exe .\build\asterisk_devbuild.pdb > NUL 2> NUL

jai .\build.jai -natvis - bake_font