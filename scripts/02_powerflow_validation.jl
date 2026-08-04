# Fase 2 — Flujo de carga AC del System físico (export PF) y validación contra
# la referencia de PowerFactory (referencia_loadflow.csv, escenario P20).
# Compuerta de calidad: |ΔV| < 0.005 pu en barras >= 69 kV.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerFlows
using CSV, DataFrames, Statistics
using SeniSienna

raw_dir = joinpath(@__DIR__, "..", "data", "raw")
val_dir = joinpath(@__DIR__, "..", "validation")
# Bloque I: punto de operación P20 exacto extraído en la VM (mismo escenario
# que referencia_loadflow.csv)
op_dir = joinpath(raw_dir, "salida_bloqueI_edac_20260717_111009")

sys, forname_to_bus, stactrl_spec = build_seni_physical_system(raw_dir; op_dir)
to_json(sys, joinpath(@__DIR__, "..", "data", "sys", "seni_fisico.json"); force = true)

# ---- flujo AC con límites de reactiva (iopt_lim=1) y control secundario ------
# de tensión (ElmStactrl): en cada iteración (a) se ajustan las consignas PV de
# las máquinas de cada controlador para clavar su nodo piloto (el reactivo
# fluye desde los terminales reales) y (b) lazo clásico PV→PQ de límites de Q.
function solve_with_controls!(sys, spec; max_iter = 25, k = 0.7)
    num2bus = Dict(get_number(b) => b for b in get_components(ACBus, sys))
    bus_by_name = Dict(get_name(b) => b for b in get_components(ACBus, sys))
    gens_by_bus = Dict(get_name(get_bus(g)) => g
                       for g in get_components(ThermalStandard, sys))
    res = nothing
    for it in 1:max_iter
        res = solve_powerflow(ACPowerFlow(), sys)
        br = res["bus_results"]
        qcols = [c for c in names(br) if occursin("Q_gen", string(c))]
        isempty(qcols) && (println("  columnas: ", names(br)); error("sin columna Q_gen"))
        qcol = first(qcols)
        v_by_num = Dict(r.bus_number => r.Vm for r in eachrow(br))

        # (a) control secundario: consignas de miembros hacia el piloto
        max_err = 0.0
        for sc in spec
            pb = bus_by_name[sc.pilot_bus]
            err = sc.vset - v_by_num[get_number(pb)]
            max_err = max(max_err, abs(err))
            abs(err) < 0.001 && continue
            for mb in sc.member_buses
                b = bus_by_name[mb]
                get_bustype(b) == ACBusTypes.PV || continue  # los PQ ya saturaron
                # terminales de máquina no operan bajo 0.95 pu (PF tampoco
                # alcanza consignas piloto bajas: p. ej. Boca Chica 0.94)
                set_magnitude!(b, clamp(get_magnitude(b) + k * err, 0.95, 1.1))
            end
        end

        # (b) límites de reactiva PV→PQ
        conmutados = 0
        for r in eachrow(br)
            bus = num2bus[r.bus_number]
            get_bustype(bus) == ACBusTypes.PV || continue
            g = get(gens_by_bus, get_name(bus), nothing)
            g === nothing && continue
            lim = get_reactive_power_limits(g)   # MVar (unidades naturales)
            q = r[qcol]
            if q > lim.max + 0.5
                set_reactive_power!(g, lim.max)
                set_bustype!(bus, ACBusTypes.PQ)
                conmutados += 1
            elseif q < lim.min - 0.5
                set_reactive_power!(g, lim.min)
                set_bustype!(bus, ACBusTypes.PQ)
                conmutados += 1
            end
        end
        println("  iter ", it, ": err_piloto_max = ", round(max_err; digits = 4),
                "  PV→PQ = ", conmutados)
        (conmutados == 0 && max_err < 0.001) && break
    end
    return res
end

set_units_base_system!(sys, "NATURAL_UNITS")
res = solve_with_controls!(sys, stactrl_spec)
bus_res = res["bus_results"]
println("Flujo AC resuelto: ", nrow(bus_res), " barras")

# V por nombre de barra del System
name_by_number = Dict(get_number(b) => get_name(b) for b in get_components(ACBus, sys))
kv_by_number = Dict(get_number(b) => get_base_voltage(b) for b in get_components(ACBus, sys))
v_by_bus = Dict(name_by_number[r.bus_number] => r.Vm for r in eachrow(bus_res))

# ---- referencia PowerFactory (P20) -------------------------------------------
ref_dir = joinpath(raw_dir, "salida_dinamica_20260714", "salida_dinamica_20260714_203429")
ref = CSV.read(joinpath(ref_dir, "referencia_loadflow.csv"), DataFrame)
ref = ref[.!ismissing.(ref.barra_for_name) .&& startswith.(coalesce.(string.(ref.barra_for_name), ""), "W"), :]
ref_v = combine(groupby(ref, :barra_for_name),
                :V_pu => mean => :v_pf, :U_nom_kV => first => :kv)

# ---- comparación por for_name -------------------------------------------------
rows = NamedTuple[]
for r in eachrow(ref_v)
    fn = string(r.barra_for_name)
    haskey(forname_to_bus, fn) || continue
    bname = forname_to_bus[fn]
    haskey(v_by_bus, bname) || continue
    push!(rows, (for_name = fn, kv = r.kv, v_pf = r.v_pf,
                 v_sienna = v_by_bus[bname], dv = v_by_bus[bname] - r.v_pf))
end
cmp = DataFrame(rows)
CSV.write(joinpath(val_dir, "fase2_delta_v.csv"), sort(cmp, :dv, by = abs, rev = true))

alta = cmp[cmp.kv .>= 69.0, :]
println("\n── Validación Fase 2 (vs PowerFactory P20) ──")
println("  Barras comparadas: ", nrow(cmp), " (", nrow(alta), " en ≥69 kV)")
println("  |ΔV| medio  (≥69 kV): ", round(mean(abs.(alta.dv)); digits = 5), " pu")
println("  |ΔV| máximo (≥69 kV): ", round(maximum(abs.(alta.dv)); digits = 5), " pu")
println("  Barras ≥69 kV con |ΔV| > 0.005 pu: ", count(abs.(alta.dv) .> 0.005))
println("\nPeores 15:")
show(first(sort(alta, :dv, by = abs, rev = true), 15); allrows = true, allcols = true)
println()
