# Barrido 2 — Estudio de SOBREDESLASTRE del EDAC en PSID.
#
# El SENI deslastra abriendo circuitos completos. En el RMS de referencia de PF
# (pérdida de Punta Catalina 2, 360 MW) los relés de etapa 1 DISPARAN pero no
# abren nada (no hay interruptores conectados en el modelo PF). Aquí ejecutamos
# esa acción en Sienna:
#   Sim A: pérdida de PC2 sin EDAC (línea base, = script 08)
#   Sim B: pérdida de PC2 + apertura de los alimentadores de los 13 relés que
#          dispararon en la referencia (LoadTrip en sus tiempos observados)
# Métricas: MW deslastrados vs 360 MW perdidos (ratio de sobredeslastre),
# nadir, sobrefrecuencia y f final de cada caso.
#
# Nota v1: el disparo se toma de la observación de PF (t≈3.2 s) porque el nadir
# COI de Sienna v1 (59.46 Hz, governors típicos) no cruza 59.30 Hz por sí solo.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerSimulationsDynamics, Sundials
using CSV, DataFrames, Statistics, Plots
using SeniSienna

raw_dir = joinpath(@__DIR__, "..", "data", "raw")
val_dir = joinpath(@__DIR__, "..", "validation")
edac_dir = joinpath(raw_dir, "seni_extraccion_vm_20260717",
                    "salida_bloqueI_edac_20260717_111009")
rms_dir = joinpath(raw_dir, "seni_extraccion_vm_20260717",
                   "salida_rms_edac_20260717_113111")

# ---- relés disparados en la referencia y sus tiempos --------------------------
disparos = CSV.read(joinpath(rms_dir, "rms_edac_disparos_reles.csv"), DataFrame)
t_por_rele = Dict{String,Float64}()
for r in eachrow(disparos)
    obj = split(String(r.objeto), "\\")[end]
    endswith(obj, ".ElmRelay") || continue
    rele = replace(obj, ".ElmRelay" => "")
    haskey(t_por_rele, rele) || (t_por_rele[rele] = r.t_s)
end
println("Relés disparados en la referencia PF: ", length(t_por_rele))

# ---- etapas 1 activas de esos relés → cargas a abrir --------------------------
edac = CSV.read(joinpath(edac_dir, "edac_detalle.csv"), DataFrame)
etapas = edac[(edac.activa_efectiva .== 1) .&
              (abs.(coalesce.(edac.f_arranque_hz, 0.0) .- 59.3) .< 0.05) .&
              [String(r) in keys(t_por_rele) for r in edac.relay_root], :]
println("Etapas 1 activas de esos relés: ", nrow(etapas),
        "  (ΣMW tabla P20: ", round(sum(skipmissing(etapas.MW_deslastrados)); digits = 1), ")")

# ---- system físico con capa dinámica ------------------------------------------
sys, _ = build_seni_physical_system(raw_dir)
attach_dynamic_models!(sys, raw_dir)

loads_by_loc = Dict{String,StandardLoad}()
for l in get_components(StandardLoad, sys)
    loc = replace(get_name(l), r"^load_\d+_" => "")
    loads_by_loc[loc] = l
end

function _find_gen(sys, patron)
    for g in get_components(ThermalStandard, sys)
        maqs = get(get_ext(g), "maquinas", NamedTuple[])
        any(m -> occursin(patron, m.loc_name), maqs) && return g
    end
    return nothing
end
pc2 = _find_gen(sys, "Punta Catalina 2")
pc2 === nothing && error("No se encontró Punta Catalina 2")

# cargas del deslastre mapeadas a StandardLoad de Sienna
aperturas = NamedTuple[]
no_map = String[]
for row in eachrow(etapas)
    String(row.objeto_clase) == "ElmLod" || continue
    loc = String(row.objeto_disparado)
    load = get(loads_by_loc, loc, nothing)
    if load === nothing
        push!(no_map, loc)
        continue
    end
    t_trip = t_por_rele[String(row.relay_root)]
    p_mw = get_impedance_active_power(load)  # MW (attach dejó unidades naturales)
    push!(aperturas, (rele = String(row.relay_root), carga = loc,
                      t_s = t_trip, p_mw = p_mw, load = load))
end
mw_total = sum(a.p_mw for a in aperturas)
println("Cargas mapeadas: ", length(aperturas), " (sin mapear: ", length(no_map),
        ")  MW a abrir: ", round(mw_total; digits = 1))

# ---- simulaciones -------------------------------------------------------------
function correr(perturbaciones)
    s = first(build_seni_physical_system(raw_dir))
    attach_dynamic_models!(s, raw_dir)
    perts = PowerSimulationsDynamics.Perturbation[]
    for p in perturbaciones
        if p.tipo == :gen
            g = get_component(DynamicGenerator, s, p.nombre)
            push!(perts, GeneratorTrip(p.t, g))
        else
            push!(perts, LoadTrip(p.t, get_component(StandardLoad, s, p.nombre)))
        end
    end
    sim = Simulation(ResidualModel, s, mktempdir(), (0.0, 30.0), perts)
    st = execute!(sim, IDA(linear_solver = :KLU); saveat = 0.02)
    occursin("FINALIZED", string(st)) || error("Simulación no completó: " * string(st))
    res = read_results(sim)
    num = nothing; den = 0.0; tiempo = nothing
    for dyn in get_components(DynamicGenerator, s)
        get_name(dyn) == get_name(pc2) && continue
        stat = get_component(ThermalStandard, s, get_name(dyn))
        hs = get_H(get_shaft(dyn)) * get_base_power(stat)
        t, ω = get_state_series(res, (get_name(dyn), :ω))
        tiempo = t
        num = num === nothing ? hs .* ω : num .+ hs .* ω
        den += hs
    end
    return collect(tiempo), 60.0 .* num ./ den
end

evento_pc2 = (tipo = :gen, nombre = get_name(pc2), t = 1.0)
println("\nSim A (sin EDAC)...")
tA, fA = correr([evento_pc2])
println("Sim B (con aperturas EDAC de la referencia)...")
tB, fB = correr(vcat([evento_pc2],
                     [(tipo = :load, nombre = get_name(a.load), t = a.t_s)
                      for a in aperturas]))

# ---- métricas y salidas --------------------------------------------------------
resumen = DataFrame(
    caso = ["A: sin EDAC", "B: con EDAC (aperturas PF)"],
    nadir_hz = [minimum(fA), minimum(fB)],
    f_max_hz = [maximum(fA), maximum(fB)],
    f_final_hz = [fA[end], fB[end]],
    mw_deslastrados = [0.0, round(mw_total; digits = 1)],
)
CSV.write(joinpath(val_dir, "barrido2_edac_resumen.csv"), resumen)
# series por separado: el integrador añade puntos extra en los eventos de Sim B
CSV.write(joinpath(val_dir, "barrido2_edac_serie_sin.csv"),
          DataFrame(t_s = tA, f_hz = fA))
CSV.write(joinpath(val_dir, "barrido2_edac_serie_con.csv"),
          DataFrame(t_s = tB, f_hz = fB))
CSV.write(joinpath(val_dir, "barrido2_edac_aperturas.csv"),
          DataFrame([(rele = a.rele, carga = a.carga, t_s = a.t_s,
                      p_mw = round(a.p_mw; digits = 2)) for a in aperturas]))

# Ventana física válida: tras cruzar ~61.5 Hz dispararía generación por
# sobrefrecuencia (no modelada en v1) → el tramo posterior no es creíble.
const C_SIENNA = RGB(0.255, 0.412, 0.882)
p = plot(tA, fA; color = :gray40, lw = 2, label = "sin EDAC",
         xlabel = "Tiempo (s)", ylabel = "Frecuencia (Hz)",
         title = "Sobredeslastre EDAC — pérdida PC2 (360 MW)",
         legend = :topright, size = (900, 500),
         xlims = (0, 8), ylims = (59.1, 62.5))
plot!(p, tB, fB; color = C_SIENNA, lw = 2,
      label = "con EDAC (aperturas PF, " * string(round(Int, mw_total)) * " MW)")
hline!(p, [60.0]; color = :gray70, ls = :dot, label = "")
hline!(p, [59.3]; color = :firebrick, ls = :dash, label = "escalón 1 EDAC (59.3 Hz)")
hline!(p, [61.5]; color = :darkorange, ls = :dash,
       label = "sobrefrecuencia: disparo de generación (~61.5 Hz)")
savefig(p, joinpath(val_dir, "figuras", "f6_edac_sobredeslastre.png"))

println("\n── Barrido 2: sobredeslastre EDAC ──")
show(resumen; allrows = true, allcols = true)
println("\n  Pérdida: 360 MW  |  Deslastre etapa 1 (13 relés): ",
        round(mw_total; digits = 1), " MW  |  ratio = ",
        round(mw_total / 360; digits = 2), "×")
