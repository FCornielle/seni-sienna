# Fase 0 — Instala las dependencias Sienna en el entorno del proyecto.
# Uso:  julia scripts/00_setup_environment.jl
# (Requiere Julia >= 1.10; en Windows instalar con `winget install julia -s msstore` o juliaup)

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

Pkg.add([
    # Sienna\Data
    "PowerSystems",
    "PowerFlows",
    "PowerNetworkMatrices",
    # Sienna\Ops
    "PowerSimulations",
    "StorageSystemsSimulations",
    "HydroPowerSimulations",
    # Sienna\Dyn
    "PowerSimulationsDynamics",
    # Utilidades Sienna
    "PowerSystemCaseBuilder",
    "PowerGraphics",
    "PowerAnalytics",
    # Solver y herramientas
    "HiGHS",
    "CSV",
    "DataFrames",
    "TimeSeries",
    "JSON3",
])

Pkg.instantiate()
Pkg.precompile()

# Verificación rápida del entorno con un caso de prueba de NREL
println("\n--- Verificando entorno con PowerSystemCaseBuilder (RTS-GMLC) ---")
using PowerSystemCaseBuilder
sys = build_system(PSISystems, "modified_RTS_GMLC_DA_sys")
println(sys)
println("\n✅ Entorno Sienna listo.")
