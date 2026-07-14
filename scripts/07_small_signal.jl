# Fase 5 — Estabilidad de pequeña señal con PowerSimulationsDynamics.jl:
# eigenvalores, frecuencias y amortiguamiento de modos electromecánicos.
# Comparar contra el estudio de pequeña señal de PowerFactory.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerSimulationsDynamics
using SeniSienna

sys = System(joinpath(@__DIR__, "..", "data", "sys", "seni_base.json"))
# TODO Fase 5:
#  attach_dynamic_models!(sys, pf_dir)  # capa dinámica (dynamics_library.jl)
#  sim = Simulation(ResidualModel, sys, mktempdir(), (0.0, 1.0))
#  ss = small_signal_analysis(sim)
#  reportar modos: frecuencia, ζ; comparar con PowerFactory
error("TODO Fase 5: análisis de pequeña señal")
