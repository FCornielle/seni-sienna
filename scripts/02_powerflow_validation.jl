# Fase 2 — Flujo de carga AC del System físico (export PF) y validación contra
# la referencia de PowerFactory (referencia_loadflow.csv, escenario P20).
# Compuerta de calidad: |ΔV| < 0.005 pu en barras >= 69 kV.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerFlows
using CSV, DataFrames, Statistics
using SeniSienna

raw_dir = joinpath(@__DIR__, "..", "data", "raw")
val_dir = joinpath(@__DIR__, "..", "validation")

sys, forname_to_bus = build_seni_physical_system(raw_dir)
to_json(sys, joinpath(@__DIR__, "..", "data", "sys", "seni_fisico.json"); force = true)

# ---- flujo AC (con cumplimiento de límites de reactiva, como PowerFactory) ---
res = try
    solve_powerflow(ACPowerFlow(; check_reactive_power_limits = true), sys)
catch err
    @warn "check_reactive_power_limits no soportado; flujo sin límites de Q" err
    solve_powerflow(ACPowerFlow(), sys)
end
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
