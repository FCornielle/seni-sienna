# Fase 1 — Series temporales: demanda nodal (factores VEROPE), perfiles
# solar/eólico. 24/48 snapshots como SingleTimeSeries; versión Deterministic
# para simulaciones secuenciales día-adelante → despacho.

"""
    attach_demand_timeseries!(sys::System, processed_dir::AbstractString)

Demanda por barra: serie base del sistema × factor nodal VEROPE,
adjunta como SingleTimeSeries a cada PowerLoad.
"""
function attach_demand_timeseries!(sys::System, processed_dir::AbstractString)
    error("TODO Fase 1: demanda nodal horaria")
end

"""
    attach_renewable_timeseries!(sys::System, processed_dir::AbstractString)

Perfiles horarios solar/eólico como SingleTimeSeries de max_active_power.
"""
function attach_renewable_timeseries!(sys::System, processed_dir::AbstractString)
    error("TODO Fase 1: perfiles renovables horarios")
end
