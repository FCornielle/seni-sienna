# Validación por escenario P01–P24: compara el despacho de Sienna (ED, script 03)
# con los 24 puntos de operación de PowerFactory (`op_generacion_P01_P24.csv`,
# Ronda 2 VM, PDD 30-09-2025). Como Sienna corre sobre la capa canónica MODOM y
# los P01–P24 son de PF, se matchean por **nivel de demanda** (mismo load → mismo
# punto de despacho); el mix por combustible se compara por par ordenado.
#
#   julia --project=. scripts/16_validacion_p01_p24.jl

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using CSV, DataFrames, Statistics

raw_dir = joinpath(@__DIR__, "..", "data", "raw")
val_dir = joinpath(@__DIR__, "..", "validation")
op_dir = joinpath(raw_dir, "salida_op_P01_P24_20260804_191945")

# ---- clasificación por combustible (por nombre de planta, espejo de 03/15) ----
_norm(s) = uppercase(replace(string(s), r"[ÁÀÄ]"i => "A", r"[ÉÈË]"i => "E",
    r"[ÍÌÏ]"i => "I", r"[ÓÒÖ]"i => "O", r"[ÚÙÜ]"i => "U", "Ñ" => "N", "ñ" => "N"))
const _GAS = ("SIBA", "LOS MINA", "MANZANILLO", "SEABOARD", "ENERGAS", "ESTRELLA",
    "QUISQUEYA", "SAN PEDRO VAPOR")
const FUELS = ["Carbón", "Fuel Oil / Diesel", "Gas Natural", "Biomasa", "Hidro", "Eólica", "Solar", "Otra"]
function fuel(nombre)
    n = _norm(nombre)
    (occursin("PUNTA CATALINA", n) || occursin("BARAHONA", n) ||
        (occursin("ITABO", n) && !occursin("TG", n))) && return "Carbón"
    occursin(r"SOLAR|FOTOVOLT", n) && return "Solar"
    occursin(r"EOLIC|VIENTO|LOS COCOS|JUANCHO|QUILVIO|GUANILLO|MATAFONGO|AGUA CLARA|GUZMANCITO|LARIMAR|PECASA", n) && return "Eólica"
    (occursin("BIO", n) || occursin("INGENIO", n) || occursin("BAGAZO", n)) && return "Biomasa"
    occursin(r"AGUACATE|JIGUEY|VALDESIA|TAVERA|PALOMINO|MONCION|RIO BLANCO|PINALITO|HATILLO|ANGOSTURA|SABANA|SABANETA|RINCON|BAIGUAQUE|ANIANA|DOMINGO RODRIGUEZ|LAS DAMAS|LAS BARIAS|BRAZO|NIZAO|NAJAYO|MAGUEYAL|JIMENOA|EL SALTO|CONTRA|LOS TOROS|LOS ANONES|MAGUACA", n) && return "Hidro"
    occursin("GN", n) && return "Gas Natural"
    (occursin("FO", n) || occursin("FUEL", n) || occursin("DIESEL", n)) && return "Fuel Oil / Diesel"
    any(w -> occursin(w, n), _GAS) && return "Gas Natural"
    return "Fuel Oil / Diesel"
end

# ---- PF: agrega op_generacion por combustible y escenario ---------------------
opg = CSV.read(joinpath(op_dir, "op_generacion_P01_P24.csv"), DataFrame)
res = CSV.read(joinpath(op_dir, "resumen_por_escenario.csv"), DataFrame)
escs = sort(unique(String.(opg.escenario)))
pf_mix = Dict(e => Dict(f => 0.0 for f in FUELS) for e in escs)
for r in eachrow(opg)
    (!ismissing(r.outserv) && r.outserv == 1) && continue
    p = ismissing(r.P_desp_MW) ? 0.0 : Float64(r.P_desp_MW)
    p <= 0 && continue
    pf_mix[String(r.escenario)][fuel(String(r.loc_name))] += p
end
pf_dem = Dict(String(r.escenario) => Float64(r.demanda_P_MW) for r in eachrow(res))

# ---- Sienna: mix por hora (despacho_fuel_hora.csv del ED) ---------------------
sf = CSV.read(joinpath(val_dir, "despacho_fuel_hora.csv"), DataFrame)
si_mix = [Dict(f => (Symbol(f) in propertynames(sf) ? Float64(sf[h, Symbol(f)]) : 0.0) for f in FUELS)
          for h in 1:nrow(sf)]
si_dem = Float64.(sf.demanda)

# ---- matcheo por rango de demanda --------------------------------------------
pf_ord = sort(escs; by = e -> pf_dem[e])
si_ord = sortperm(si_dem)
n = min(length(pf_ord), length(si_ord))

# NOTA: en `op_generacion_P01_P24` el despacho de los `genstat` (renovables) viene
# en 0 → la comparación válida es solo el **síncrono (térmico+hidro)**.
const SYNC = ["Carbón", "Fuel Oil / Diesel", "Gas Natural", "Biomasa", "Hidro"]
filas = NamedTuple[]
ov = Float64[]; sv = Float64[]
for k in 1:n
    e = pf_ord[k]; h = si_ord[k]
    pf_t = sum(pf_mix[e][f] for f in SYNC); si_t = sum(si_mix[h][f] for f in SYNC)
    for f in SYNC; push!(ov, pf_mix[e][f]); push!(sv, si_mix[h][f]); end
    push!(filas, (escenario = e, hora_sienna = h,
                  demanda_PF = round(pf_dem[e]; digits = 0), demanda_Si = round(si_dem[h]; digits = 0),
                  sinc_PF = round(pf_t; digits = 0), sinc_Si = round(si_t; digits = 0),
                  delta_pct = round(100 * (si_t - pf_t) / pf_t; digits = 1)))
end
cmp = DataFrame(filas)
CSV.write(joinpath(val_dir, "p01_p24_validacion.csv"), cmp)

# R² del síncrono total siguiendo la curva de carga (24 escenarios). El R² por
# combustible no es limpio por el swap gas↔fuel-oil (dual-fuel) y la clasificación
# por lado; el seguimiento del total síncrono sí valida la respuesta a la demanda.
r2 = let o = cmp.sinc_PF, s = cmp.sinc_Si
    1 - sum((o .- s) .^ 2) / sum((o .- mean(o)) .^ 2)
end
mae = mean(abs.(cmp.sinc_PF .- cmp.sinc_Si))

# energía por combustible en los 24 escenarios
efila = NamedTuple[]
for f in FUELS
    pe = sum(pf_mix[e][f] for e in escs); se = sum(si_mix[h][f] for h in 1:nrow(sf))
    (pe < 1 && se < 1) && continue
    push!(efila, (combustible = f, PF_GWh = round(pe / 1000; digits = 2),
                  sienna_GWh = round(se / 1000; digits = 2),
                  delta_pct = pe > 1 ? round(100 * (se - pe) / pe; digits = 1) : NaN))
end
emix = DataFrame(efila)
CSV.write(joinpath(val_dir, "p01_p24_mix.csv"), emix)

println("── Validación por escenario P01–P24 (Sienna ED vs puntos de operación PF) ──")
println("  Escenarios matcheados por demanda: ", n, "  (síncrono térmico+hidro;")
println("  renovables excluidas: el P_desp de genstat viene en 0 en la extracción)")
show(cmp; allrows = true, allcols = true)
println("\n\n· Energía por combustible (24 escenarios; renovables PF≈0 por lo anterior):")
show(emix; allrows = true, allcols = true)
println("\n  R² del síncrono total vs demanda (24 escenarios): ", round(r2; digits = 4),
        "  · MAE ", round(mae; digits = 0), " MW")
println("  Síncrono total PF: ", round(sum(cmp.sinc_PF) / 1000; digits = 1), " GWh · Sienna: ",
        round(sum(cmp.sinc_Si) / 1000; digits = 1), " GWh (Δ ",
        round(100 * (sum(cmp.sinc_Si) - sum(cmp.sinc_PF)) / sum(cmp.sinc_PF); digits = 1), "%)")
println("\n  Nota: el swap Gas↔Fuel-Oil (dual-fuel) y la renovable no capturada en")
println("  la extracción (genstat P_desp=0) impiden un R² por combustible limpio.")

# JSON para el dashboard
using JSON3
resumen = Dict("n" => n, "r2" => round(r2; digits = 4), "mae" => round(mae; digits = 0),
    "pf_GWh" => round(sum(ov) / 1000; digits = 2), "sienna_GWh" => round(sum(sv) / 1000; digits = 2),
    "por_escenario" => [Dict(pairs(r)...) for r in eachrow(cmp)],
    "mix" => [Dict(pairs(r)...) for r in eachrow(emix)])
open(joinpath(val_dir, "p01_p24_validacion.json"), "w") do io; JSON3.pretty(io, resumen); end
println("\n✓ validation/p01_p24_validacion.{csv,json} + p01_p24_mix.csv")
