# Carga de trabajo para la sysimage: ejercita las rutas calientes del proyecto
# (construcción del System, flujo AC y utilidades) para que queden compiladas.
using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerFlows, PowerNetworkMatrices
using CSV, DataFrames, JSON3
using SeniSienna

raw = joinpath(@__DIR__, "..", "data", "raw")
if isdir(joinpath(raw, "processed"))
    sys = build_seni_dispatch_system(raw)
    length(get_components(ACBus, sys))
end
if isdir(joinpath(raw, "salida_PDD_30_09_2025"))
    sysf = first(build_seni_physical_system(raw))
    try
        solve_powerflow(ACPowerFlow(), sysf)
    catch
    end
end
println("workload ok")
