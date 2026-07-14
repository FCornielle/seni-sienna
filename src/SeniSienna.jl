"""
    SeniSienna

Recreación del SENI (Sistema Eléctrico Nacional Interconectado, República
Dominicana) en la plataforma Sienna (NREL).

Fuentes de datos (en `data/raw/`, no versionadas):
- Exportaciones CSV del modelo PowerFactory (`salida_PDD_*`)
- Tablas canónicas MODOM del proyecto modom-pypsa (`data/processed/`)

Ver `PLAN_SENI_SIENNA.md` para el plan completo por fases.
"""
module SeniSienna

using CSV
using DataFrames
using Dates
using PowerSystems

const PSY = PowerSystems

# Fase 1 — traducción de datos
include("parse_powerfactory.jl")
include("parse_modom.jl")
include("timeseries.jl")
include("build_system.jl")

# Fase 5 — capa dinámica
include("dynamics_library.jl")

export build_seni_system

end # module
