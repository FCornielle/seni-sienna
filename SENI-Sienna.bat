@echo off
rem Lanzador del dashboard SENI-Sienna
rem Usa la sysimage precompilada si existe (arranque en segundos);
rem si no, arranque normal de Julia.
setlocal
cd /d "%~dp0"
set JULIA=%LOCALAPPDATA%\Programs\Julia-1.12.6\bin\julia.exe
if not exist "%JULIA%" set JULIA=julia

start "" http://localhost:8155
if exist "sysimage\SeniSienna_sys.dll" (
    echo [SENI-Sienna] arrancando con sysimage precompilada...
    "%JULIA%" --project=. -J "sysimage\SeniSienna_sys.dll" scripts\12_dashboard.jl
) else (
    echo [SENI-Sienna] arrancando ^(sin sysimage; ejecuta scripts\13_build_sysimage.jl para acelerar^)...
    "%JULIA%" --project=. scripts\12_dashboard.jl
)
