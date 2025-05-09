set ARGS=

IF "%~1"=="profile" (
    set ARGS=-plug Iprof %ARGS%
)
IF "%~1"=="profile-full" (
    set ARGS=-plug Iprof -modules %ARGS%
)