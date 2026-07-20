# Construye la sysimage precompilada (arranque del dashboard y de los scripts
# en segundos en lugar de minutos). Tarda 30–60 min; correr una vez por
# actualización de dependencias:
#
#   julia --project=. scripts/13_build_sysimage.jl
#
# Salida: sysimage/SeniSienna_sys.dll (no versionada; ~1 GB). El lanzador
# SENI-Sienna.bat la usa automáticamente si existe.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PackageCompiler

root = normpath(joinpath(@__DIR__, ".."))
mkpath(joinpath(root, "sysimage"))

create_sysimage(
    [:PowerSystems, :PowerSimulations, :PowerSimulationsDynamics, :PowerFlows,
     :PowerNetworkMatrices, :HydroPowerSimulations, :HiGHS, :Sundials,
     :CSV, :DataFrames, :JuMP, :Plots, :Oxygen, :HTTP, :JSON3];
    sysimage_path = joinpath(root, "sysimage", "SeniSienna_sys.dll"),
    precompile_execution_file = joinpath(root, "scripts", "precompile_workload.jl"),
)
println("Sysimage lista: sysimage/SeniSienna_sys.dll")
