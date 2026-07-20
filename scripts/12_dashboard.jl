# Dashboard SENI-Sienna — plataforma de corridas y resultados (≙ webapp de
# modom-pypsa, en Julia con Oxygen.jl).
#
#   julia --project=. scripts/12_dashboard.jl        (o SENI-Sienna.bat)
#   → http://localhost:8155
#
# Pestañas: Corridas (lanza los scripts 01–11 como subprocesos, estado y log en
# vivo), Resultados (figuras + tablas de validation/), Reporte (consolidado).

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using Oxygen, HTTP, JSON3, CSV, DataFrames, Dates

const ROOT = normpath(joinpath(@__DIR__, ".."))
const VAL = joinpath(ROOT, "validation")
const FIGS = joinpath(VAL, "figuras")
const LOGS = joinpath(ROOT, "data", "logs")
mkpath(LOGS)
const JULIA_EXE = joinpath(Sys.BINDIR, "julia.exe")

# ---- catálogo de corridas ----------------------------------------------------
const CORRIDAS = [
    (id = "build",     script = "01_build_system.jl",        nombre = "Construir System (MODOM)",
     desc = "717 barras, generadores, series, reservas y flowgates → data/sys/"),
    (id = "flujo",     script = "02_powerflow_validation.jl", nombre = "Flujo AC vs PowerFactory",
     desc = "System físico P20 + control secundario + límites Q; ΔV vs referencia"),
    (id = "ed",        script = "03_dispatch_ed.jl",          nombre = "Despacho ED (commitment fijo)",
     desc = "LP DC 24h vs MODOM — R² objetivo ≥ 0.94"),
    (id = "uc",        script = "04_uc_milp.jl",              nombre = "UC MILP + reservas RPF/RSF",
     desc = "Commitment binario con PowerSimulations + HiGHS"),
    (id = "n1",        script = "05_contingency_n1.jl",       nombre = "Contingencias N-1",
     desc = "Screening LODF + AC en críticas, veredicto por deltas"),
    (id = "qds",       script = "06_quasi_dynamic_24h.jl",    nombre = "Cuasi-dinámico 24h",
     desc = "24 flujos AC con perfil horario; envolvente de tensión"),
    (id = "pequena",   script = "07_small_signal.jl",         nombre = "Pequeña señal",
     desc = "Eigenvalores y amortiguamiento vs análisis modal de PF"),
    (id = "frecuencia", script = "08_transient_frequency.jl", nombre = "Respuesta de frecuencia",
     desc = "Pérdida de Punta Catalina 2 — nadir vs 59.285 Hz de PF"),
    (id = "reporte",   script = "09_report.jl",               nombre = "Reporte + figuras",
     desc = "REPORTE_SENI_SIENNA.md consolidado con veredictos"),
    (id = "edac",      script = "10_edac_sobredeslastre.jl",  nombre = "EDAC: sobredeslastre",
     desc = "Aperturas reales de etapa 1 (502 MW) vs pérdida de 360 MW"),
    (id = "selectivo", script = "11_deslastre_selectivo.jl",  nombre = "Deslastre selectivo",
     desc = "EDAC actual vs 30% por alimentador (figura f7)"),
]
const POR_ID = Dict(c.id => c for c in CORRIDAS)

# ---- job runner ---------------------------------------------------------------
mutable struct Job
    estado::String   # corriendo | ok | error
    log::String
    inicio::DateTime
    fin::Union{Nothing,DateTime}
end
const JOBS = Dict{String,Job}()
const LOCK = ReentrantLock()

function lanzar(id::String)
    c = POR_ID[id]
    lock(LOCK) do
        haskey(JOBS, id) && JOBS[id].estado == "corriendo" && return false
        log = joinpath(LOGS, "$(id)_$(Dates.format(now(), "yyyymmdd_HHMMSS")).log")
        JOBS[id] = Job("corriendo", log, now(), nothing)
        @async begin
            ok = try
                cmd = Cmd(`$JULIA_EXE --project=$ROOT $(joinpath(ROOT, "scripts", c.script))`;
                          dir = ROOT)
                run(pipeline(cmd; stdout = log, stderr = log))
                true
            catch
                false
            end
            lock(LOCK) do
                JOBS[id].estado = ok ? "ok" : "error"
                JOBS[id].fin = now()
            end
        end
        return true
    end
end

# ---- API ----------------------------------------------------------------------
@get "/api/corridas" function ()
    lock(LOCK) do
        [(id = c.id, nombre = c.nombre, desc = c.desc, script = c.script,
          estado = haskey(JOBS, c.id) ? JOBS[c.id].estado : "—",
          inicio = haskey(JOBS, c.id) ? string(JOBS[c.id].inicio) : "",
          fin = haskey(JOBS, c.id) && JOBS[c.id].fin !== nothing ?
                string(JOBS[c.id].fin) : "")
         for c in CORRIDAS]
    end
end

@post "/api/corridas/{id}" function (req, id::String)
    haskey(POR_ID, id) || return HTTP.Response(404, "corrida desconocida")
    lanzado = lanzar(id)
    return (ok = lanzado, id = id)
end

@get "/api/log/{id}" function (req, id::String)
    j = lock(LOCK) do
        get(JOBS, id, nothing)
    end
    j === nothing && return (texto = "(sin corridas aún)",)
    texto = isfile(j.log) ? read(j.log, String) : ""
    lineas = split(texto, '\n')
    return (texto = join(last(lineas, min(80, length(lineas))), '\n'),)
end

@get "/api/resultados" function ()
    figs = isdir(FIGS) ? sort(filter(f -> endswith(f, ".png"), readdir(FIGS))) : String[]
    csvs = isdir(VAL) ? sort(filter(f -> endswith(f, ".csv"), readdir(VAL))) : String[]
    mds = isdir(VAL) ? sort(filter(f -> endswith(f, ".md"), readdir(VAL))) : String[]
    return (figuras = figs, tablas = csvs, docs = mds)
end

@get "/api/tabla/{nombre}" function (req, nombre::String)
    path = joinpath(VAL, basename(nombre))
    (isfile(path) && endswith(path, ".csv")) || return HTTP.Response(404)
    df = CSV.read(path, DataFrame; limit = 200)
    return (columnas = names(df),
            filas = [[string(df[i, c]) for c in names(df)] for i in 1:nrow(df)])
end

@get "/figuras/{nombre}" function (req, nombre::String)
    path = joinpath(FIGS, basename(nombre))
    isfile(path) || return HTTP.Response(404)
    return HTTP.Response(200, ["Content-Type" => "image/png"]; body = read(path))
end

@get "/api/doc/{nombre}" function (req, nombre::String)
    path = joinpath(VAL, basename(nombre))
    (isfile(path) && endswith(path, ".md")) || return HTTP.Response(404)
    return (texto = read(path, String),)
end

@get "/" function ()
    html = read(joinpath(ROOT, "dashboard", "index.html"), String)
    return HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"]; body = html)
end

println("SENI-Sienna dashboard → http://localhost:8155")
serve(host = "127.0.0.1", port = 8155)
