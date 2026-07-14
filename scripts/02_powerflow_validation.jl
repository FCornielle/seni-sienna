# Fase 2 — Flujo de carga AC (PowerFlows.jl) sobre el snapshot base y comparación
# contra PowerFactory / pandapower (modom-pypsa).
# Compuerta de calidad: |ΔV| < 0.005 pu en barras >= 69 kV antes de pasar a Fase 3.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerFlows

sys = System(joinpath(@__DIR__, "..", "data", "sys", "seni_base.json"))

result = solve_powerflow(ACPowerFlow(), sys)
# TODO Fase 2:
#  - exportar tensiones/ángulos por barra a validation/
#  - cargar referencia (resultados pandapower de modom-pypsa) y calcular ΔV
#  - reportar barras fuera de tolerancia
error("TODO Fase 2: comparación contra referencia PowerFactory/pandapower")
