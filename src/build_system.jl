# Fase 1 — Ensamblaje y validación del System completo del SENI.

"""
    build_seni_system(raw_dir; base_power=100.0) -> System

Construye el System del SENI a partir de `data/raw/`:
1. Componentes de red desde el export PowerFactory (salida_PDD_*)
2. Datos operativos MODOM (costos, rampas, commitment) por for_name
3. Series temporales de demanda y renovables
4. Reservas RPF/RSF y flowgates

Valida conteos contra resumen.csv antes de devolver.
"""
function build_seni_system(raw_dir::AbstractString; base_power::Float64 = 100.0)
    pf_dir = _find_pf_export(raw_dir)
    tables = read_pf_export(pf_dir)

    sys = System(base_power)
    add_buses!(sys, tables)
    add_lines!(sys, tables)
    add_transformers!(sys, tables)
    add_loads!(sys, tables)
    add_generators!(sys, tables)
    add_shunts!(sys, tables)

    processed = joinpath(raw_dir, "processed")
    apply_modom_operational_data!(sys, processed)
    add_flowgates!(sys, processed)
    attach_demand_timeseries!(sys, processed)
    attach_renewable_timeseries!(sys, processed)

    validate_counts(sys, tables)
    return sys
end

"Encuentra la carpeta salida_PDD_* más reciente dentro de raw_dir."
function _find_pf_export(raw_dir::AbstractString)
    dirs = filter(d -> startswith(basename(d), "salida_PDD"),
                  readdir(raw_dir; join = true))
    isempty(dirs) && error("No se encontró ninguna carpeta salida_PDD_* en $raw_dir. " *
                           "Copia el export de PowerFactory según data/raw/README.md")
    return last(sort(dirs))
end

"Compara conteos de componentes del System contra resumen.csv del export."
function validate_counts(sys::System, tables::Dict{String,DataFrame})
    error("TODO Fase 1: validación de conteos vs resumen.csv")
end
