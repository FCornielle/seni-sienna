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
    (id = "escenario", script = "14_scenario_studio.jl",      nombre = "Scenario Studio (UC)",
     desc = "UC con perillas de escenario y delta vs línea base"),
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

# ---- Scenario Studio ----------------------------------------------------------
const OV_FILE = joinpath(ROOT, "data", "scenario_overrides.json")

@get "/api/generadores" function ()
    path = joinpath(ROOT, "data", "raw", "processed", "generators", "generators.csv")
    isfile(path) || return (generadores = [],)
    df = CSV.read(path, DataFrame)
    # solo térmicos despachables con capacidad (los que el UC puede apagar)
    filas = [(id = string(r.generator_id), nombre = string(r.generator_name),
              pmax = round(Float64(r.effective_pmax_mw); digits = 1))
             for r in eachrow(df)
             if string(r.technology_group) in ("1", "3") &&
                !ismissing(r.effective_pmax_mw) && Float64(r.effective_pmax_mw) > 20]
    return (generadores = sort(filas; by = f -> -f.pmax),)
end

@get "/api/escenario" function ()
    ov = isfile(OV_FILE) ? JSON3.read(read(OV_FILE, String)) : nothing
    res = joinpath(VAL, "scenario_resumen.csv")
    resumen = isfile(res) ? (df = CSV.read(res, DataFrame);
        (columnas = names(df),
         filas = [[string(df[i, c]) for c in names(df)] for i in 1:nrow(df)])) : nothing
    return (overrides = ov, resumen = resumen)
end

@post "/api/escenario" function (req)
    body = json(req)
    open(OV_FILE, "w") do io; JSON3.write(io, body); end
    lanzar("escenario")
    return (ok = true,)
end

# ---- Mapa (barras georreferenciadas + capa de resultados) --------------------
function _coords()
    path = joinpath(ROOT, "data", "raw", "buses_with_coords.csv")
    isfile(path) || return DataFrame()
    df = CSV.read(path, DataFrame)
    df[.!ismissing.(df.lat) .& .!ismissing.(df.lon), :]
end

@get "/api/mapa" function (req)
    capa = get(queryparams(req), "capa", "kv")
    df = _coords()
    nrow(df) == 0 && return (barras = [], con_dato = 0)

    # capa vpu: tensión del flujo de la Fase 2 (por for_name)
    vmap = Dict{String,Float64}()
    f2 = joinpath(VAL, "fase2_delta_v.csv")
    if capa == "vpu" && isfile(f2)
        d2 = CSV.read(f2, DataFrame)
        for r in eachrow(d2); vmap[String(r.for_name)] = Float64(r.v_sienna); end
    end
    # capa edac: MW deslastrables por barra (etapas activas del EDAC, por W-code)
    edmap = Dict{String,Float64}()
    ed_csv = joinpath(ROOT, "data", "raw", "seni_extraccion_vm_20260717",
                      "salida_bloqueI_edac_20260717_111009", "edac_detalle.csv")
    if capa == "edac" && isfile(ed_csv)
        d = CSV.read(ed_csv, DataFrame)
        for r in eachrow(d)
            (!ismissing(r.activa_efectiva) && r.activa_efectiva == 1) || continue
            # W-code de la barra: terminal_for_name, o `terminal` sin sufijo "(N)"
            bf = ismissing(r.terminal_for_name) ? "" : String(r.terminal_for_name)
            isempty(bf) && !ismissing(r.terminal) &&
                (bf = replace(String(r.terminal), r"\(\d+\)" => ""))
            mw = ismissing(r.MW_deslastrados) ? 0.0 : Float64(r.MW_deslastrados)
            startswith(bf, "W") || continue
            edmap[bf] = get(edmap, bf, 0.0) + mw
        end
    end

    fl(x, d) = (x === missing || x === nothing) ? d : Float64(x)
    con = Ref(0)
    barras = map(eachrow(df)) do r
        id = String(r.bus_id_modom)
        v = get(vmap, id, nothing);  v !== nothing && (con[] += 1)
        ed = get(edmap, id, 0.0);    capa == "edac" && ed > 0 && (con[] += 1)
        capa == "kv" && (con[] += 1)
        (id = id, nombre = ismissing(r.bus_name) ? id : String(r.bus_name),
         kv = fl(r.v_nom_kv, 0.0), lat = fl(r.lat, 0.0), lon = fl(r.lon, 0.0),
         vpu = v, edac_mw = ed)
    end
    return (barras = barras, con_dato = con[])
end

# ---- Feed OC (procedencia de datos) ------------------------------------------
@get "/api/feed_oc" function ()
    raw = joinpath(ROOT, "data", "raw")
    chk(p) = isdir(joinpath(raw, p)) || isfile(joinpath(raw, p))
    return (items = [
        (nombre = "Export PowerFactory (PDD 30-09-2025)", ok = chk("salida_PDD_30_09_2025"),
         origen = "VM DIgSILENT / OC 5.CASOS DIGSILENT"),
        (nombre = "Tablas canónicas MODOM", ok = chk("processed"),
         origen = "workbook MODOM (VEROPE + PDD del OC)"),
        (nombre = "Extracción dinámica (DSL, EDAC)", ok = chk("salida_dinamica_20260714"),
         origen = "VM DIgSILENT"),
        (nombre = "Bloque I + EDAC detalle (P20)", ok = chk("seni_extraccion_vm_20260717"),
         origen = "VM DIgSILENT"),
    ], recurso = "https://www.dropbox.com/sh/sel2bzf89wc3dyu (OC — Programación del SENI)")
end

# ---- Red de transmisión (segmentos línea para el mapa) -----------------------
@get "/api/red" function ()
    df = _coords()
    nrow(df) == 0 && return (segmentos = [],)
    coord = Dict(String(r.bus_id_modom) => (Float64(r.lat), Float64(r.lon)) for r in eachrow(df))
    kv = Dict(String(r.bus_id_modom) => (ismissing(r.v_nom_kv) ? 0.0 : Float64(r.v_nom_kv)) for r in eachrow(df))
    brf = joinpath(ROOT, "data", "raw", "processed", "branches", "branches.csv")
    isfile(brf) || return (segmentos = [],)
    br = CSV.read(brf, DataFrame)
    segs = NamedTuple[]
    for r in eachrow(br)
        fb, tb = String(r.from_bus), String(r.to_bus)
        (haskey(coord, fb) && haskey(coord, tb) && fb != tb) || continue
        v = max(get(kv, fb, 0.0), get(kv, tb, 0.0))
        push!(segs, (from = [coord[fb]...], to = [coord[tb]...], kv = v,
                     tipo = String(r.branch_type), nombre = String(r.branch_id)))
    end
    return (segmentos = segs,)
end

# ---- Series horarias / resultados para gráficos interactivos -----------------
_valcsv(n) = (p = joinpath(VAL, n); isfile(p) ? CSV.read(p, DataFrame) : nothing)
_asbool(x) = x === true || x == 1 || (x isa AbstractString && lowercase(x) == "true")

@get "/api/serie/{tipo}" function (req, tipo::String)
    if tipo == "despacho_tec"
        d = _valcsv("despacho_tec_hora.csv"); d === nothing && return (horas = [],)
        return (horas = d.hora, termica = d.termica, hidro = d.hidro,
                renovable = d.renovable, demanda = d.demanda)
    elseif tipo == "commitment"
        d = _valcsv("fase3b_uc_comparison.csv"); d === nothing && return (unidades = [],)
        horas = sort(unique(Int.(d.hora)))
        units = String[]; on = Dict{String,Vector{Int}}()
        for r in eachrow(d)
            g = String(r.gen); v = _asbool(r.sienna_on) ? 1 : 0
            haskey(on, g) || (push!(units, g); on[g] = zeros(Int, length(horas)))
            on[g][Int(r.hora)] = v
        end
        act = [u for u in units if sum(on[u]) > 0]           # solo con algún ON
        sort!(act; by = u -> -sum(on[u]))
        return (unidades = act, horas = horas, matriz = [on[u] for u in act])
    elseif tipo == "tension"
        d = _valcsv("fase4_qds_resumen.csv"); d === nothing && return (horas = [],)
        return (horas = d.hora, v_min = d.v_min, v_max = d.v_max, fuera = d.fuera_banda)
    elseif tipo == "frecuencia"
        out = Dict{String,Any}(); etq = ("sin" => "Sin EDAC", "edac" => "EDAC actual", "sel" => "Selectivo")
        for (k, _) in etq
            d = _valcsv("v2_selectivo_serie_$k.csv")
            d !== nothing && (out[k] = [[d.t_s[i], d.f_hz[i]] for i in 1:nrow(d)])
        end
        return (series = out,)
    elseif tipo == "pequena"
        d = _valcsv("fase5_small_signal_sienna.csv"); d === nothing && return (modos = [],)
        em = d[(d.frecuencia_hz .> 0.1) .& (d.frecuencia_hz .< 3.0), :]
        return (modos = [(f = em.frecuencia_hz[i], z = em.amortiguamiento_pct[i]) for i in 1:nrow(em)],)
    elseif tipo == "n1"
        d = _valcsv("fase4_n1_screening.csv"); d === nothing && return (items = [],)
        d = sort(d, :sobrecargas_nuevas, rev = true)[1:min(12, nrow(d)), :]
        return (items = [(c = String(d.contingencia[i]), n = d.sobrecargas_nuevas[i],
                          kv = d.kv[i]) for i in 1:nrow(d)],)
    elseif tipo == "despacho_unidad"
        d = _valcsv("fase3_dispatch_comparison.csv"); d === nothing && return (unidades = [],)
        tot = Dict{String,Float64}()
        for r in eachrow(d); tot[String(r.gen)] = get(tot, String(r.gen), 0.0) + r.sienna; end
        top = sort(collect(keys(tot)); by = g -> -tot[g])[1:min(10, length(tot))]
        horas = sort(unique(Int.(d.hora)))
        mw = Dict(g => zeros(Float64, length(horas)) for g in top)
        for r in eachrow(d); haskey(mw, String(r.gen)) && (mw[String(r.gen)][Int(r.hora)] = r.sienna); end
        return (unidades = top, horas = horas, series = [mw[g] for g in top])
    end
    return HTTP.Response(404, "serie desconocida")
end

# ---- KPIs para la vista de operación -----------------------------------------
@get "/api/kpis" function ()
    k = Pair{String,Any}[]
    d = _valcsv("despacho_tec_hora.csv")
    if d !== nothing
        push!(k, "Demanda pico" => string(round(maximum(d.demanda); digits = 0), " MW"))
        push!(k, "Generación térmica" => string(round(sum(d.termica) / 1000; digits = 1), " GWh/día"))
        push!(k, "Renovable" => string(round(sum(d.renovable) / 1000; digits = 1), " GWh/día"))
    end
    t = _valcsv("fase4_qds_resumen.csv")
    t !== nothing && push!(k, "Tensión mín 24h" => string(round(minimum(t.v_min); digits = 3), " pu"))
    f = _valcsv("v2_selectivo_resumen.csv")
    f !== nothing && push!(k, "Nadir (pérdida PC2)" => string(round(minimum(f.nadir_hz); digits = 3), " Hz"))
    return (kpis = [(k = p.first, v = p.second) for p in k],)
end

# SPA Preact+htm en dashboard/spa (no-build; stack vendorizado localmente).
const SPA = joinpath(ROOT, "dashboard", "spa")
const _MIME = Dict(".js" => "application/javascript; charset=utf-8", ".css" => "text/css; charset=utf-8",
    ".html" => "text/html; charset=utf-8", ".png" => "image/png", ".svg" => "image/svg+xml",
    ".json" => "application/json", ".woff" => "font/woff", ".woff2" => "font/woff2",
    ".map" => "application/json", ".ico" => "image/x-icon")
_mime(f) = get(_MIME, lowercase(splitext(f)[2]), "application/octet-stream")

# sirve dashboard/spa (app.js, styles.css, index.html) y dashboard/spa/vendor
@get "/spa/{file}" function (req, file::String)
    f = joinpath(SPA, basename(file))
    isfile(f) || return HTTP.Response(404)
    return HTTP.Response(200, ["Content-Type" => _mime(f)]; body = read(f))
end
@get "/spa/vendor/{file}" function (req, file::String)
    f = joinpath(SPA, "vendor", basename(file))
    isfile(f) || return HTTP.Response(404)
    return HTTP.Response(200, ["Content-Type" => _mime(f)]; body = read(f))
end
@get "/spa/vendor/fonts/{file}" function (req, file::String)
    f = joinpath(SPA, "vendor", "fonts", basename(file))
    isfile(f) || return HTTP.Response(404)
    return HTTP.Response(200, ["Content-Type" => _mime(f)]; body = read(f))
end

@get "/" function ()
    spa = joinpath(SPA, "index.html")
    html = isfile(spa) ? read(spa, String) :
           read(joinpath(ROOT, "dashboard", "index.html"), String)
    return HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"]; body = html)
end

println("SENI-Sienna dashboard → http://localhost:8155")
serve(host = "127.0.0.1", port = 8155)
