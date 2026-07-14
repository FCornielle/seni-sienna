# Fase 1 — Enriquecimiento con datos operativos MODOM (modom-pypsa/data/processed/)
#
# Mapeo por `for_name` (mismo patrón probado en modom-pypsa para inyectar en
# pandapower): costos CVP, rampas, min up/down, arranques, disponibilidad,
# commitment, reservas RPF/RSF y flowgates (e_fgate).

"""
    apply_modom_operational_data!(sys::System, processed_dir::AbstractString)

Asigna a los generadores del System sus parámetros operativos MODOM:
curvas de costo (CVP), rampas, tiempos mínimos, costos de arranque.
"""
function apply_modom_operational_data!(sys::System, processed_dir::AbstractString)
    error("TODO Fase 1: mapear tablas canónicas MODOM por for_name")
end

"""
    add_reserves!(sys::System, processed_dir::AbstractString)

Crea servicios VariableReserve{ReserveUp}/{ReserveDown} para RPF y RSF
con sus requisitos horarios y asigna las unidades participantes.
"""
function add_reserves!(sys::System, processed_dir::AbstractString)
    error("TODO Fase 3: reservas RPF/RSF co-optimizadas")
end

"""
    add_flowgates!(sys::System, processed_dir::AbstractString)

Crea TransmissionInterface por cada flowgate de e_fgate
(fg1 ≤ 200 MW, fg2 ≤ 670 MW) sobre sus grupos de líneas.
"""
function add_flowgates!(sys::System, processed_dir::AbstractString)
    error("TODO Fase 1: flowgates como TransmissionInterface")
end
