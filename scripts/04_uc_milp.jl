# Fase 3 — UC MILP completo con reservas RPF/RSF co-optimizadas (≙ Layer 2b,
# y cierra el pendiente de reservas de modom-pypsa).
# BESS: StorageSystemsSimulations. Hidro: HydroPowerSimulations.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerSimulations, HiGHS
using StorageSystemsSimulations, HydroPowerSimulations

sys = System(joinpath(@__DIR__, "..", "data", "sys", "seni_base.json"))

template = ProblemTemplate(NetworkModel(PTDFPowerModel))
set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template, PowerLoad, StaticPowerLoad)
set_device_model!(template, Line, StaticBranch)
# TODO Fase 3:
#  - set_service_model! para VariableReserve{ReserveUp}/{ReserveDown} (RPF/RSF)
#  - StorageDispatchWithReserves para BESS, modelos hidro
#  - opcional: Simulation secuencial día-adelante → despacho con feedforward

error("TODO Fase 3: build!/solve! UC MILP y validación de costos")
