# Fase 4 — Contingencias N-1 sobre el System físico (export PowerFactory):
#  1. Screening DC con LODF (PowerNetworkMatrices) sobre todas las ramas de
#     transmisión (>= 69 kV): flujo post = f_l + LODF[l,k] · f_k
#  2. AC completo (PowerFlows) en las contingencias más críticas
#  3. Veredicto por deltas (Código de Conexión): solo cuentan sobrecargas
#     nuevas o empeoradas y tensiones fuera de 0.95–1.05 pu nuevas
#
# Las contingencias que aíslan carga (LODF no finito / radiales) se reportan
# aparte como "islanding".

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerFlows, PowerNetworkMatrices
using CSV, DataFrames, Statistics
using SeniSienna

val_dir = joinpath(@__DIR__, "..", "validation")
raw_dir = joinpath(@__DIR__, "..", "data", "raw")

sys, _ = build_seni_physical_system(raw_dir)
set_units_base_system!(sys, "NATURAL_UNITS")

branches = [br for T in (Line, Transformer2W, TapTransformer)
            for br in get_components(T, sys) if get_available(br)]
kv(br) = min(get_base_voltage(get_from(get_arc(br))),
             get_base_voltage(get_to(get_arc(br))))
rating_mw(br) = get_rating(br)   # MVA en unidades naturales

# ---- flujo base AC ------------------------------------------------------------
res = solve_powerflow(ACPowerFlow(), sys)
fr = res["flow_results"]
pcol = first([c for c in names(fr) if occursin("P_from_to", c)])
base_flow = Dict(String(r.line_name) => r[pcol] for r in eachrow(fr))
base_load_pct = Dict(get_name(br) =>
    100 * abs(get(base_flow, get_name(br), 0.0)) / max(rating_mw(br), 1e-3)
    for br in branches)

# ---- LODF ----------------------------------------------------------------------
lodf = LODF(sys)
lnames = PowerNetworkMatrices.get_branch_ax(lodf)
lidx = Dict(String(n) => i for (i, n) in enumerate(lnames))

monitored = [br for br in branches if rating_mw(br) < 5_000 && haskey(lidx, get_name(br))]
outages = [br for br in branches if kv(br) >= 69.0 && haskey(lidx, get_name(br))]
println("Ramas monitoreadas: ", length(monitored), "  Contingencias: ", length(outages))

rows = NamedTuple[]
islanding = String[]
for out in outages
    ko = lidx[get_name(out)]
    fk = get(base_flow, get_name(out), 0.0)
    worst_pct = 0.0; worst_br = ""; nuevas = 0
    ok = true
    for mon in monitored
        get_name(mon) == get_name(out) && continue
        lm = lodf[lidx[get_name(mon)], ko]
        if !isfinite(lm)
            ok = false
            break
        end
        post = get(base_flow, get_name(mon), 0.0) + lm * fk
        pct = 100 * abs(post) / max(rating_mw(mon), 1e-3)
        if pct > 100 && base_load_pct[get_name(mon)] <= 100
            nuevas += 1
        end
        if pct > worst_pct
            worst_pct = pct; worst_br = get_name(mon)
        end
    end
    if !ok
        push!(islanding, get_name(out))
        continue
    end
    push!(rows, (contingencia = get_name(out), kv = kv(out),
                 flujo_base_mw = round(fk; digits = 1),
                 sobrecargas_nuevas = nuevas,
                 peor_carga_pct = round(worst_pct; digits = 1),
                 peor_rama = worst_br))
end
scr = sort(DataFrame(rows), :sobrecargas_nuevas, rev = true)
CSV.write(joinpath(val_dir, "fase4_n1_screening.csv"), scr)
println("Screening N-1: ", nrow(scr), " contingencias evaluadas, ",
        length(islanding), " con islanding, ",
        count(scr.sobrecargas_nuevas .> 0), " producen sobrecargas nuevas (DC)")

# ---- AC en las críticas ----------------------------------------------------------
criticas = first(scr[scr.sobrecargas_nuevas .> 0, :contingencia], 10)
ac_rows = NamedTuple[]
for cname in criticas
    br = nothing
    for T in (Line, Transformer2W, TapTransformer)
        br = get_component(T, sys, cname)
        br !== nothing && break
    end
    br === nothing && continue
    set_available!(br, false)
    result = try
        r = solve_powerflow(ACPowerFlow(), sys)
        vres = r["bus_results"]
        nv = count((vres.Vm .< 0.95) .| (vres.Vm .> 1.05))
        fr2 = r["flow_results"]
        over = 0
        for rr in eachrow(fr2)
            b2 = nothing
            for T in (Line, Transformer2W, TapTransformer)
                b2 = get_component(T, sys, String(rr.line_name))
                b2 !== nothing && break
            end
            b2 === nothing && continue
            pct = 100 * abs(rr[pcol]) / max(get_rating(b2), 1e-3)
            (pct > 100 && get(base_load_pct, String(rr.line_name), 0.0) <= 100) && (over += 1)
        end
        (convergio = true, v_fuera = nv, sobrecargas = over)
    catch
        (convergio = false, v_fuera = -1, sobrecargas = -1)
    end
    set_available!(br, true)
    push!(ac_rows, (contingencia = cname, convergio = result.convergio,
                    tensiones_fuera_banda = result.v_fuera,
                    sobrecargas_nuevas_ac = result.sobrecargas))
end
ac = DataFrame(ac_rows)
CSV.write(joinpath(val_dir, "fase4_n1_ac.csv"), ac)
println("\n── Fase 4: N-1 ──")
println("Top contingencias críticas (verificación AC):")
show(ac; allrows = true, allcols = true)
println()
