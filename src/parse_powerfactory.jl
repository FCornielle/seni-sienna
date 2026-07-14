# Fase 1 — Traductor de exportaciones CSV de PowerFactory a componentes PowerSystems.jl
#
# Archivos de entrada (data/raw/salida_PDD_*/):
#   barras.csv                → ACBus
#   lineas.csv + tipos_lineas.csv → Line
#   transformadores2.csv + tipos  → Transformer2W / TapTransformer
#   transformadores3.csv          → equivalente estrella (3×2W + barra ficticia)
#   cargas.csv                → PowerLoad
#   generadores_sinc.csv      → ThermalStandard / HydroDispatch
#   generadores_est.csv       → RenewableDispatch / EnergyReservoirStorage
#   shunts.csv, svc.csv       → FixedAdmittance / compensación
#
# Cuidados: impedancias a pu en base 100 MVA, taps, signos de shunts.

"""
    read_pf_export(dir::AbstractString) -> Dict{String,DataFrame}

Lee todos los CSVs relevantes de una carpeta `salida_PDD_*` y los devuelve
como DataFrames indexados por nombre de tabla.
"""
function read_pf_export(dir::AbstractString)
    tables = Dict{String,DataFrame}()
    for name in ("barras", "lineas", "tipos_lineas", "transformadores2",
                 "tipos_transformadores2", "transformadores3", "cargas",
                 "tipos_cargas", "generadores_sinc", "tipos_generadores",
                 "generadores_est", "shunts", "svc", "resumen")
        path = joinpath(dir, name * ".csv")
        isfile(path) && (tables[name] = CSV.read(path, DataFrame))
    end
    return tables
end

function add_buses!(sys::System, tables::Dict{String,DataFrame})
    error("TODO Fase 1: crear ACBus desde barras.csv")
end

function add_lines!(sys::System, tables::Dict{String,DataFrame})
    error("TODO Fase 1: crear Line desde lineas.csv + tipos_lineas.csv")
end

function add_transformers!(sys::System, tables::Dict{String,DataFrame})
    error("TODO Fase 1: Transformer2W; 3W como estrella equivalente")
end

function add_loads!(sys::System, tables::Dict{String,DataFrame})
    error("TODO Fase 1: crear PowerLoad desde cargas.csv")
end

function add_generators!(sys::System, tables::Dict{String,DataFrame})
    error("TODO Fase 1: ThermalStandard/HydroDispatch/RenewableDispatch/BESS")
end

function add_shunts!(sys::System, tables::Dict{String,DataFrame})
    error("TODO Fase 1: FixedAdmittance desde shunts.csv y svc.csv")
end
