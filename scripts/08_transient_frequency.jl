# Fase 5 — Transitorios RMS con PSID:
#  a) Falla trifásica + despeje (tiempo crítico de despeje)
#  b) Pérdida del mayor generador → nadir de frecuencia vs 59.2 Hz,
#     con EDAC modelado como deslastre por pasos
#  c) Hueco de tensión en el punto de interconexión de una planta PV+BESS

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerSimulationsDynamics
using SeniSienna

sys = System(joinpath(@__DIR__, "..", "data", "sys", "seni_base.json"))
# TODO Fase 5:
#  attach_dynamic_models!(sys, pf_dir)
#  perturbaciones: BranchTrip, GeneratorTrip, y deslastre EDAC por pasos
#  criterio: nadir >= 59.2 Hz (primer escalón EDAC, Código de Conexión)
error("TODO Fase 5: simulaciones transitorias y de frecuencia")
