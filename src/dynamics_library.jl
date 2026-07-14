# Fase 5 — Capa dinámica: mapeo de modelos DSL de PowerFactory (ElmDsl.csv)
# a modelos estándar de PowerSimulationsDynamics.jl (PSID).
#
# Síncronos → DynamicGenerator (máquina GENROU/GENSAL + shaft + AVR + governor + PSS)
# Inversores → DynamicInverter (WECC genéricos: REGCA + REECB + REPCA; grid-forming)
#
# Estrategia incremental: primero las 10–20 máquinas más grandes, resto agregado.
# Donde falten parámetros → valores típicos por tecnología, documentados aquí.

"""
    attach_dynamic_models!(sys::System, pf_dir::AbstractString; top_n=20)

Adjunta modelos dinámicos PSID a los `top_n` generadores de mayor capacidad,
tomando parámetros de ElmDsl.csv / tipos_generadores.csv cuando existan.
Cada supuesto (parámetro típico) queda registrado en el log de supuestos.
"""
function attach_dynamic_models!(sys::System, pf_dir::AbstractString; top_n::Int = 20)
    error("TODO Fase 5: mapeo DSL → PSID")
end
