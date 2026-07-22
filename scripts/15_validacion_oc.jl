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
using HTTP, JSON3, CSV, DataFrames, Statistics

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

# ---- tira el post-despacho real del OC ----------------------------------------
println("Consultando OC: post-despacho de $fecha …")
r = HTTP.get(OC * fecha; readtimeout = 40, retries = 2)
data = JSON3.read(String(r.body)).GetPostDespacho
println("Centrales del OC: ", length(data))

oc_mix = Dict(f => zeros(Float64, 24) for f in FUELS)
oc_por_central = Dict{String,Vector{Float64}}()
n_plantas = 0
for row in data
    grupo = String(get(row, :GRUPO, ""))
    occursin("TOTAL", _norm(grupo)) && continue   # filas de resumen del OC, no centrales
    f = fuel(get(row, :CENTRAL, ""), grupo)
    hs = [Float64(get(row, Symbol("H$h"), 0.0)) for h in 1:24]
    oc_mix[f] .+= hs
    oc_por_central[String(get(row, :CENTRAL, ""))] = hs
    global n_plantas += 1
end
println("Centrales reales (sin subtotales): ", n_plantas)

# ---- Sienna: mix por combustible (despacho ED) --------------------------------
sf = CSV.read(joinpath(val_dir, "despacho_fuel_hora.csv"), DataFrame)
si_mix = Dict(f => (Symbol(f) in propertynames(sf) ? Float64.(sf[!, Symbol(f)]) : zeros(24)) for f in FUELS)

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

# JSON para el dashboard (pestaña "Validación OC")
resumen = Dict(
    "fecha" => fecha, "fuente" => "OC · GetPostDespachoJSon (apps.oc.org.do)",
    "n_centrales" => n_plantas,
    "oc_GWh" => round(sum(oc_tot) / 1000; digits = 2),
    "sienna_GWh" => round(sum(si_tot) / 1000; digits = 2),
    "delta_total_pct" => round(100 * (sum(si_tot) - sum(oc_tot)) / sum(oc_tot); digits = 1),
    "r2_horario" => round(r2; digits = 4),
    "grupo" => [Dict(pairs(r)...) for r in eachrow(cmp_coarse)],
    "fuel" => [Dict(pairs(r)...) for r in eachrow(cmp)],
    "oc_hora" => Dict(f => round.(oc_mix[f]; digits = 1) for f in FUELS if sum(oc_mix[f]) > 1),
    "sienna_hora" => Dict(f => round.(si_mix[f]; digits = 1) for f in FUELS if sum(si_mix[f]) > 1))
open(joinpath(val_dir, "oc_validacion.json"), "w") do io
    JSON3.pretty(io, resumen)
end
println("\n✓ validation/oc_validacion.json escrito (pestaña dashboard)")
