# Fase 3 — Despacho económico con commitment fijo de MODOM (≙ Layer 2a de modom-pypsa).
# Red PTDF, flowgates activos. Meta: R² >= 0.94 vs despacho MODOM real.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerSimulations, HiGHS

sys = System(joinpath(@__DIR__, "..", "data", "sys", "seni_base.json"))

template = ProblemTemplate(NetworkModel(PTDFPowerModel))
set_device_model!(template, ThermalStandard, ThermalBasicDispatch)
set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template, PowerLoad, StaticPowerLoad)
set_device_model!(template, Line, StaticBranch)
# TODO Fase 3: fijar commitment MODOM (parámetros de estado), hidro, BESS,
# TransmissionInterface de flowgates.

problem = DecisionModel(template, sys;
                        optimizer = optimizer_with_attributes(HiGHS.Optimizer),
                        horizon = Hour(24))
error("TODO Fase 3: build!/solve! y comparación R² vs MODOM/PyPSA")
