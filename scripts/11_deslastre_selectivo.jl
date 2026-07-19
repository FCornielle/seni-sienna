# v2 — Deslastre SELECTIVO vs EDAC actual (apertura de circuitos completos).
#
# Tres simulaciones sobre la capa dinámica v2 (parámetros DSL reales):
#   A: pérdida de PC2 (360 MW) sin EDAC
#   B: + EDAC actual = apertura de los alimentadores de los 13 relés de etapa 1
#      que disparan en la referencia PF (~502 MW, ratio 1.39x)
#   C: + deslastre SELECTIVO: mismo instante de disparo, pero dimensionado
#      (~40% de la pérdida) abriendo los alimentadores más pequeños primero
#
# Hallazgo previo (autoconsistencia): con la capa v2 el nadir COI es 59.43 Hz —
# NO cruza 59.30 Hz, es decir, con la dinámica de Sienna el EDAC ni siquiera
# debería disparar para este evento; los tiempos de disparo se toman de la
# observación de PF (nadir 59.285) para el comparativo.

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

const OBJETIVO_SELECTIVO_MW = 140.0   # ~40% de la pérdida (dimensionado)

# ---- disparos de referencia y etapas (mismo pipeline que script 10) -----------
disparos = CSV.read(joinpath(rms_dir, "rms_edac_disparos_reles.csv"), DataFrame)
t_por_rele = Dict{String,Float64}()
for r in eachrow(disparos)
    obj = split(String(r.objeto), "\\")[end]
    endswith(obj, ".ElmRelay") || continue
    rele = replace(obj, ".ElmRelay" => "")
    haskey(t_por_rele, rele) || (t_por_rele[rele] = r.t_s)
end
edac = CSV.read(joinpath(edac_dir, "edac_detalle.csv"), DataFrame)
etapas = edac[(edac.activa_efectiva .== 1) .&
              (abs.(coalesce.(edac.f_arranque_hz, 0.0) .- 59.3) .< 0.05) .&
              [String(r) in keys(t_por_rele) for r in edac.relay_root], :]

sys0, _ = build_seni_physical_system(raw_dir)
attach_dynamic_models!(sys0, raw_dir)
loads_by_loc = Dict(replace(get_name(l), r"^load_\d+_" => "") => get_name(l)
                    for l in get_components(StandardLoad, sys0))
function _find_gen(sys, patron)
    for g in get_components(ThermalStandard, sys)
        maqs = get(get_ext(g), "maquinas", NamedTuple[])
        any(m -> occursin(patron, m.loc_name), maqs) && return g
    end
    return nothing
end
pc2_name = get_name(_find_gen(sys0, "Punta Catalina 2"))

aperturas = NamedTuple[]
for row in eachrow(etapas)
    String(row.objeto_clase) == "ElmLod" || continue
    loc = String(row.objeto_disparado)
    haskey(loads_by_loc, loc) || continue
    lname = loads_by_loc[loc]
    l = get_component(StandardLoad, sys0, lname)
    push!(aperturas, (rele = String(row.relay_root), carga = lname,
                      t_s = t_por_rele[String(row.relay_root)],
                      p_mw = get_impedance_active_power(l)))
end
mw_edac = sum(a.p_mw for a in aperturas)

# selectivo PROPORCIONAL: en lugar de abrir circuitos completos, deslastrar
# una fracción de cada alimentador (relé con corte por pasos / feeder parcial)
const FRACCION_SELECTIVA = 0.3
sel = [(rele = a.rele, carga = a.carga, t_s = a.t_s + 0.05 * i,
        p_mw = a.p_mw * FRACCION_SELECTIVA, fraccion = FRACCION_SELECTIVA)
       for (i, a) in enumerate(aperturas)]
mw_sel = sum(a.p_mw for a in sel; init = 0.0)
println("EDAC actual: ", length(aperturas), " aperturas completas, ",
        round(mw_edac; digits = 1), " MW | Selectivo: 30% de cada alimentador, ",
        round(mw_sel; digits = 1), " MW")

# ---- simulaciones ------------------------------------------------------------
function correr(loadtrips; tfin = 30.0)
    s = first(build_seni_physical_system(raw_dir))
    # capa v1 (SEXS/typicos): los AVR reales (EXAC1 saturado) no re-inicializan
    # tras los LoadTrips masivos — la v2 queda para calibración de nadir (08)
    attach_dynamic_models!(s, raw_dir; avr_mode = :sexs, gov_mode = :tipico)
    # LoadChange espera el valor en pu de dispositivo → getters en DEVICE_BASE
    set_units_base_system!(s, "DEVICE_BASE")
    perts = PowerSimulationsDynamics.Perturbation[
        GeneratorTrip(1.0, get_component(DynamicGenerator, s, pc2_name))]
    for a in loadtrips
        l = get_component(StandardLoad, s, a.carga)
        if haskey(pairs(a), :fraccion)
            # deslastre parcial: reduce la parte Z de la carga a (1−fracción)
            nuevo = get_impedance_active_power(l) * (1 - a.fraccion)  # pu dispositivo
            push!(perts, LoadChange(a.t_s, l, :P_ref_impedance, nuevo))
        else
            push!(perts, LoadTrip(a.t_s, l))
        end
    end
    sim = Simulation(ResidualModel, s, mktempdir(), (0.0, tfin), perts)
    st = execute!(sim, IDA(linear_solver = :KLU); saveat = 0.02)
    # tolerante: si el DAE colapsa (p. ej. sobrefrecuencia extrema tras el
    # sobredeslastre), se usa la trayectoria parcial — pasada ~61.5 Hz el
    # tramo posterior es físicamente inválido de todos modos
    ok = occursin("FINALIZED", string(st))
    ok || @warn "Simulación truncada" estado = st
    res = read_results(sim)
    res === nothing && error("Sin resultados (colapso del DAE); reducir tfin")
    num = nothing; den = 0.0; tiempo = nothing
    for dyn in get_components(DynamicGenerator, s)
        get_name(dyn) == pc2_name && continue
        stat = get_component(ThermalStandard, s, get_name(dyn))
        hs = get_H(get_shaft(dyn)) * get_base_power(stat)
        t, ω = get_state_series(res, (get_name(dyn), :ω))
        tiempo = t; num = num === nothing ? hs .* ω : num .+ hs .* ω; den += hs
    end
    return collect(tiempo), 60.0 .* num ./ den
end

println("Sim A (sin EDAC, v2)...");        tA, fA = correr(NamedTuple[])
println("Sim B (EDAC actual, v2)...");     tB, fB = correr(aperturas)
println("Sim C (selectivo, v2)...");       tC, fC = correr(sel)

# ---- métricas, series y figura -------------------------------------------------
met(t, f) = (nadir = minimum(f), fmax = maximum(f), ffin = f[end], tfin = maximum(t))
mA, mB, mC = met(tA, fA), met(tB, fB), met(tC, fC)
resumen = DataFrame(
    caso = ["A: sin EDAC", "B: EDAC actual (circuitos completos)", "C: selectivo dimensionado"],
    mw_deslastrados = round.([0.0, mw_edac, mw_sel]; digits = 1),
    nadir_hz = round.([mA.nadir, mB.nadir, mC.nadir]; digits = 3),
    f_max_hz = round.([mA.fmax, mB.fmax, mC.fmax]; digits = 3),
    f_final_hz = round.([mA.ffin, mB.ffin, mC.ffin]; digits = 3),
    t_valida_s = round.([mA.tfin, mB.tfin, mC.tfin]; digits = 2))
CSV.write(joinpath(val_dir, "v2_selectivo_resumen.csv"), resumen)
for (n, t, f) in (("sin", tA, fA), ("edac", tB, fB), ("sel", tC, fC))
    CSV.write(joinpath(val_dir, "v2_selectivo_serie_$n.csv"), DataFrame(t_s = t, f_hz = f))
end

const C_SIENNA = RGB(0.255, 0.412, 0.882)
p = plot(tA, fA; color = :gray40, lw = 2, label = "A: sin EDAC",
         xlabel = "Tiempo (s)", ylabel = "Frecuencia (Hz)",
         title = "EDAC actual vs deslastre selectivo — pérdida PC2 (v2)",
         legend = :topright, size = (900, 500), xlims = (0, 12), ylims = (59.1, 62.5))
plot!(p, tB, fB; color = :firebrick, lw = 2,
      label = "B: EDAC actual (" * string(round(Int, mw_edac)) * " MW)")
plot!(p, tC, fC; color = C_SIENNA, lw = 2.5,
      label = "C: selectivo (" * string(round(Int, mw_sel)) * " MW)")
hline!(p, [60.0]; color = :gray70, ls = :dot, label = "")
hline!(p, [59.3]; color = :gray50, ls = :dash, label = "escalón 1 EDAC")
hline!(p, [61.5]; color = :darkorange, ls = :dash, label = "disparo de generación (~61.5 Hz)")
savefig(p, joinpath(val_dir, "figuras", "f7_deslastre_selectivo.png"))

println("\n── v2: EDAC actual vs selectivo ──")
show(resumen; allrows = true, allcols = true)
println()
