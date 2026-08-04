# Validación contra el despacho REAL del OC (API pública apps.oc.org.do).
# Cierra el gap D: compara el despacho de Sienna (Fase 3) con el post-despacho
# real publicado por el OC para la MISMA fecha del modelo (PDD 30-09-2025).
#
#   julia --project=. scripts/15_validacion_oc.jl [YYYY-MM-DD]
#
# Método OC: GetPostDespachoJSon?Fecha= → por central, H1..H24 (MWh).
# Se agrega por combustible (misma clasificación que el despacho de Sienna) y se
# compara el mix horario y la energía por tecnología OC vs Sienna.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using HTTP, JSON3, CSV, DataFrames, Statistics, Dates

val_dir = joinpath(@__DIR__, "..", "validation")
fecha = length(ARGS) >= 1 ? ARGS[1] : "2025-09-30"
const OC = "https://apps.oc.org.do/wsOCWebsiteChart/Service.asmx/GetPostDespachoJSon?Fecha="

# clasificación por combustible. El OC ya entrega el GRUPO (Térmica / Eólica /
# Solar / Hidroeléctrica) → se usa para el corte grueso (coincide EXACTO con los
# subtotales "Total Térmico/Solar/Hidroeléctrica" del OC) y se subdivide la
# térmica por el sufijo de modo del nombre (…GN gas, …FO fuel-oil).
_norm(s) = uppercase(replace(string(s), r"[ÁÀÄ]"i => "A", r"[ÉÈË]"i => "E",
    r"[ÍÌÏ]"i => "I", r"[ÓÒÖ]"i => "O", r"[ÚÙÜ]"i => "U", "Ñ" => "N", "ñ" => "N"))
# plantas de gas cuyo nombre no trae sufijo de modo
const _GAS = ("SIBA", "LOS MINA", "MANZANILLO", "SEABOARD", "ENERGAS", "ESTRELLA")
function fuel(nombre, grupo)
    n = _norm(nombre); g = _norm(grupo)
    occursin("SOLAR", g) && return "Solar"
    occursin("EOLIC", g) && return "Eólica"
    occursin("HIDRO", g) && return "Hidro"
    # ---- térmica: subdividir por nombre ----
    (occursin("PUNTA CATALINA", n) || occursin("BARAHONA", n) ||
        (occursin("ITABO", n) && !occursin("TG", n))) && return "Carbón"
    (occursin("BIO", n) || occursin("INGENIO", n) || occursin("BAGAZO", n)) && return "Biomasa"
    occursin("GN", n) && return "Gas Natural"                 # …CGN/…SGN/… GN
    (occursin("FO", n) || occursin("FUEL", n) || occursin("DIESEL", n)) && return "Fuel Oil / Diesel"
    any(w -> occursin(w, n), _GAS) && return "Gas Natural"    # gas sin sufijo de modo
    return "Fuel Oil / Diesel"                                 # resto térmico
end
const FUELS = ["Carbón", "Fuel Oil / Diesel", "Gas Natural", "Biomasa", "Hidro", "Eólica", "Solar", "Otra"]

# ---- tira el post-despacho real del OC (por fecha) ----------------------------
# Devuelve (mix por combustible 24h, dict central→24h, nº de centrales reales).
# Excluye las filas de resumen del OC (GRUPO=Totales).
function traer_oc(fecha)
    r = HTTP.get(OC * fecha; readtimeout = 40, retries = 2)
    data = JSON3.read(String(r.body)).GetPostDespacho
    mix = Dict(f => zeros(Float64, 24) for f in FUELS)
    porc = Dict{String,Vector{Float64}}(); n = 0
    for row in data
        grupo = String(get(row, :GRUPO, ""))
        occursin("TOTAL", _norm(grupo)) && continue
        f = fuel(get(row, :CENTRAL, ""), grupo)
        hs = [Float64(get(row, Symbol("H$h"), 0.0)) for h in 1:24]
        mix[f] .+= hs
        porc[_norm(get(row, :CENTRAL, ""))] = hs
        n += 1
    end
    return mix, porc, n
end

println("Consultando OC: post-despacho de $fecha …")
oc_mix, oc_por_central, n_plantas = traer_oc(fecha)
println("Centrales reales (sin subtotales): ", n_plantas)

# ---- Sienna: mix por combustible (despacho ED) --------------------------------
sf = CSV.read(joinpath(val_dir, "despacho_fuel_hora.csv"), DataFrame)
si_mix = Dict(f => (Symbol(f) in propertynames(sf) ? Float64.(sf[!, Symbol(f)]) : zeros(24)) for f in FUELS)

# ---- Sienna: despacho por central (unidad × hora) -----------------------------
# Los nombres de central del OC y de Sienna comparten la convención MODOM, así que
# el matcheo por nombre normalizado es directo (validación en MW, sin moneda).
su = CSV.read(joinpath(val_dir, "despacho_unidad_hora.csv"), DataFrame)
si_central = Dict{String,Vector{Float64}}()
for r in eachrow(su)
    k = _norm(r.nombre)
    v = get!(si_central, k, zeros(Float64, 24))
    v[Int(r.hora)] = Float64(r.mw)
end

# ---- comparación --------------------------------------------------------------
filas = NamedTuple[]
for f in FUELS
    oc_e = sum(oc_mix[f]); si_e = sum(si_mix[f])
    (oc_e < 1 && si_e < 1) && continue
    push!(filas, (combustible = f, oc_GWh = round(oc_e / 1000; digits = 2),
                  sienna_GWh = round(si_e / 1000; digits = 2),
                  delta_pct = oc_e > 1 ? round(100 * (si_e - oc_e) / oc_e; digits = 1) : NaN))
end
cmp = DataFrame(filas)
CSV.write(joinpath(val_dir, "oc_validacion_mix.csv"), cmp)

# series horarias OC por combustible (para el dashboard)
serie = DataFrame(hora = 1:24)
for f in FUELS; serie[!, Symbol(f)] = round.(oc_mix[f]; digits = 1); end
CSV.write(joinpath(val_dir, "oc_mix_hora.csv"), serie)

# R² del despacho total horario (OC vs Sienna)
oc_tot = [sum(oc_mix[f][h] for f in FUELS) for h in 1:24]
si_tot = [sum(si_mix[f][h] for f in FUELS) for h in 1:24]
ss_res = sum((oc_tot .- si_tot) .^ 2); ss_tot = sum((oc_tot .- mean(oc_tot)) .^ 2)
r2 = 1 - ss_res / ss_tot

# ---- validación por central (unidad × hora, matcheo por nombre) ---------------
comunes = sort(collect(intersect(keys(oc_por_central), keys(si_central))))
oc_v = Float64[]; si_v = Float64[]; cfil = NamedTuple[]
for k in comunes
    oc_h = oc_por_central[k]; si_h = si_central[k]
    append!(oc_v, oc_h); append!(si_v, si_h)
    oe = sum(oc_h); se = sum(si_h)
    (oe < 1 && se < 1) && continue
    push!(cfil, (central = k, oc_GWh = round(oe / 1000; digits = 2),
                 sienna_GWh = round(se / 1000; digits = 2),
                 delta_GWh = round((se - oe) / 1000; digits = 2)))
end
r2_central = let ssr = sum((oc_v .- si_v) .^ 2), sst = sum((oc_v .- mean(oc_v)) .^ 2)
    sst > 0 ? 1 - ssr / sst : NaN
end
mae_central = isempty(oc_v) ? NaN : mean(abs.(oc_v .- si_v))
cmp_central = sort(DataFrame(cfil), :delta_GWh, by = abs, rev = true)
CSV.write(joinpath(val_dir, "oc_validacion_central.csv"), cmp_central)
println("\n· Por central: $(length(comunes)) unidades matcheadas | R²(unidad×hora)=",
        round(r2_central; digits = 3), " | MAE=", round(mae_central; digits = 1), " MW")

# comparación gruesa (4 grupos, = subtotales que publica el OC)
coarse(f) = f in ("Solar", "Eólica", "Hidro") ? f : "Térmica"
grupos = ["Térmica", "Solar", "Eólica", "Hidro"]
cfilas = NamedTuple[]
for gr in grupos
    oc_e = sum(sum(oc_mix[f]) for f in FUELS if coarse(f) == gr)
    si_e = sum(sum(si_mix[f]) for f in FUELS if coarse(f) == gr)
    push!(cfilas, (grupo = gr, oc_GWh = round(oc_e / 1000; digits = 2),
                   sienna_GWh = round(si_e / 1000; digits = 2),
                   delta_pct = round(100 * (si_e - oc_e) / oc_e; digits = 1)))
end
cmp_coarse = DataFrame(cfilas)
CSV.write(joinpath(val_dir, "oc_validacion_grupo.csv"), cmp_coarse)

println("\n── Validación vs despacho real del OC ($fecha) ──")
println("· Por grupo (= subtotales publicados por el OC):")
show(cmp_coarse; allrows = true, allcols = true)
println("\n· Por combustible (subdivisión térmica):")
show(cmp; allrows = true, allcols = true)
println("\n  Energía total OC: ", round(sum(oc_tot) / 1000; digits = 1), " GWh  ·  Sienna: ",
        round(sum(si_tot) / 1000; digits = 1), " GWh")
println("  R² del despacho horario total: ", round(r2; digits = 4))
open(joinpath(val_dir, "oc_validacion_resumen.txt"), "w") do io
    println(io, "Validación OC $fecha | R2 total=$r2 | OC=$(sum(oc_tot)/1000)GWh Sienna=$(sum(si_tot)/1000)GWh")
end

# ---- barrido multi-día: representatividad del día canónico -------------------
# Sienna está fijo en el punto del modelo (PDD 30-09-2025). El barrido mide, para
# una ventana de días reales del OC, la energía total y el R²(central) contra ese
# despacho fijo → cuán representativo es el día canónico y la variabilidad diaria.
si_GWh = sum(sum(si_mix[f]) for f in FUELS) / 1000
si_keys = Set(keys(si_central))
function metricas_dia(dstr)
    mix, porc, _ = traer_oc(dstr)
    oc_g = sum(sum(mix[f]) for f in FUELS) / 1000
    ov = Float64[]; sv = Float64[]
    ks = intersect(keys(porc), si_keys)
    for k in ks; append!(ov, porc[k]); append!(sv, si_central[k]); end
    r2c = length(ov) > 1 ? (let ssr = sum((ov .- sv) .^ 2), sst = sum((ov .- mean(ov)) .^ 2)
        sst > 0 ? 1 - ssr / sst : NaN end) : NaN
    return (fecha = dstr, oc_GWh = round(oc_g; digits = 2),
            delta_pct = round(100 * (si_GWh - oc_g) / oc_g; digits = 1),
            r2_central = round(r2c; digits = 3), n = length(ks))
end

n_dias = 14
d0 = Date(fecha)
dias = string.(d0 - Day(n_dias - 1) : Day(1) : d0)
println("\n── Barrido multi-día ($(dias[1]) → $(dias[end])) ──")
serie_rows = NamedTuple[]
for ds in dias
    try
        m = metricas_dia(ds); push!(serie_rows, m)
        println("  $ds  OC=$(m.oc_GWh) GWh  Δ=$(m.delta_pct)%  R²central=$(m.r2_central)  (n=$(m.n))")
    catch e
        @warn "día omitido" fecha = ds exception = e
    end
end
serie_df = DataFrame(serie_rows)
CSV.write(joinpath(val_dir, "oc_validacion_serie.csv"), serie_df)
if nrow(serie_df) > 0
    r2v = collect(skipmissing(serie_df.r2_central)); r2v = filter(!isnan, r2v)
    dv = filter(!isnan, serie_df.delta_pct)
    println("  Resumen ventana: R²central media=", round(mean(r2v); digits = 3),
            " [", round(minimum(r2v); digits = 3), ", ", round(maximum(r2v); digits = 3),
            "]  ·  |Δ energía| media=", round(mean(abs.(dv)); digits = 1), "%")
end

# JSON para el dashboard (pestaña "Validación OC")
resumen = Dict(
    "fecha" => fecha, "fuente" => "OC · GetPostDespachoJSon (apps.oc.org.do)",
    "n_centrales" => n_plantas,
    "oc_GWh" => round(sum(oc_tot) / 1000; digits = 2),
    "sienna_GWh" => round(sum(si_tot) / 1000; digits = 2),
    "delta_total_pct" => round(100 * (sum(si_tot) - sum(oc_tot)) / sum(oc_tot); digits = 1),
    "r2_horario" => round(r2; digits = 4),
    "n_central" => length(comunes),
    "r2_central" => round(r2_central; digits = 3),
    "mae_central" => round(mae_central; digits = 1),
    "central_top" => [Dict(pairs(r)...) for r in eachrow(first(cmp_central, 12))],
    "grupo" => [Dict(pairs(r)...) for r in eachrow(cmp_coarse)],
    "fuel" => [Dict(pairs(r)...) for r in eachrow(cmp)],
    "oc_hora" => Dict(f => round.(oc_mix[f]; digits = 1) for f in FUELS if sum(oc_mix[f]) > 1),
    "sienna_hora" => Dict(f => round.(si_mix[f]; digits = 1) for f in FUELS if sum(si_mix[f]) > 1),
    "serie" => [Dict(pairs(r)...) for r in eachrow(serie_df)])
open(joinpath(val_dir, "oc_validacion.json"), "w") do io
    JSON3.pretty(io, resumen)
end
println("\n✓ validation/oc_validacion.json escrito (pestaña dashboard)")
