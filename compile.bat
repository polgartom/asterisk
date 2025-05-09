@echo off

call _compilation_setup.bat %*

@echo on

jai .\build.jai %ARGS% - bake_font