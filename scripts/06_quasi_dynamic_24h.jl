# Fase 4 — Cuasi-dinámico 24h (≙ estudio QDS del Feasibility-Study):
# bucle de 24 flujos AC con demanda horaria OC + despacho de la Fase 3.
# Salidas: perfiles horarios de tensión y cargabilidad por barra/rama.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerFlows

sys = System(joinpath(@__DIR__, "..", "data", "sys", "seni_base.json"))

# TODO Fase 4:
#  for h in 1:24
#    aplicar snapshot h (demanda nodal + despacho)
#    solve_powerflow(ACPowerFlow(), sys)
#    acumular tensiones/cargabilidad
#  end
error("TODO Fase 4: bucle cuasi-dinámico 24h")
