# Fase 4 — Contingencias N-1: screening con LODF (PowerNetworkMatrices) y
# AC post-contingencia (PowerFlows) en las críticas.
# Veredicto según Código de Conexión: sin sobrecargas nuevas, tensiones 0.95–1.05 pu.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerNetworkMatrices, PowerFlows

sys = System(joinpath(@__DIR__, "..", "data", "sys", "seni_base.json"))

lodf = LODF(sys)
# TODO Fase 4:
#  - flujos post-contingencia = flujos base + LODF × flujo de la rama disparada
#  - ranking de contingencias críticas; AC completo en las top-N
#  - veredicto por deltas (lógica del Feasibility-Study)
error("TODO Fase 4: screening N-1 y veredicto")
