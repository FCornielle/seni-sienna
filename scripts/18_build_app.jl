# Construye el EJECUTABLE standalone del dashboard (PackageCompiler.create_app):
# una carpeta distribuible con `bin/SENI-Sienna.exe` que arranca sin Julia
# instalado. Tarda ~30–60 min (una vez). Complementa al sysimage (script 13, que
# sí requiere Julia). Entry point: `SeniSienna.julia_main`.
#
#   julia --project=. scripts/18_build_app.jl
#
# Salida: build_app/ (no versionada, ~2 GB). Distribuir la carpeta completa.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PackageCompiler

root = normpath(joinpath(@__DIR__, ".."))
dest = joinpath(root, "build_app")
isdir(dest) && rm(dest; recursive = true, force = true)

println("create_app → $dest  (30–60 min)…")
create_app(root, dest;
    executables = ["SENI-Sienna" => "julia_main"],
    precompile_execution_file = joinpath(root, "scripts", "precompile_workload.jl"),
    include_lazy_artifacts = true,
    force = true)

# create_app empaqueta src/ + entorno compilado, pero NO scripts/data/dashboard →
# se copian junto al .exe (julia_main los busca vía SENI_ROOT = raíz de la app).
for d in ("scripts", "dashboard", "data", "validation")
    s = joinpath(root, d)
    isdir(s) && cp(s, joinpath(dest, d); force = true)
end
# lanzador amigable
open(joinpath(dest, "SENI-Sienna.bat"), "w") do io
    println(io, "@echo off\r\ncd /d \"%~dp0\"\r\nbin\\SENI-Sienna.exe\r\npause")
end
println("\n✓ Ejecutable: ", joinpath(dest, "bin", "SENI-Sienna.exe"))
println("  Distribuir la carpeta build_app/ completa; doble-click en SENI-Sienna.bat")
