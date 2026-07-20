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
using JSON3
using TimeSeries: TimeArray
using PowerSystems

const PSY = PowerSystems

# Fase 1 — System de despacho desde las tablas canónicas MODOM
include("build_modom_system.jl")

# Fase 2 — System físico desde el export PowerFactory
include("parse_powerfactory.jl")

# Fase 5 — capa dinámica
include("dynamics_library.jl")

# Fase 6 — veredictos del Código de Conexión
include("verdicts.jl")

export build_seni_dispatch_system, build_seni_physical_system, prune_to_main_island!,
       attach_dynamic_models!,
       veredicto_tension, veredicto_sobrecargas, veredicto_amortiguamiento,
       veredicto_nadir

end # module
