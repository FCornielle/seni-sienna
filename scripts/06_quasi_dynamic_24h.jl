# Fase 4 — Cuasi-dinámico 24h (≙ estudio QDS del Feasibility-Study):
# bucle de 24 flujos AC sobre el System físico con el perfil horario de demanda
# del SENI (capa canónica MODOM). Aproximación v1: cargas y generación despachable
# escaladas por el factor horario del sistema (el punto nodal exacto por hora
# llega con el Bloque I / inyección por for_name — documentado).
#
# Salidas: perfiles horarios de tensión por barra y cargabilidad por rama.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerFlows
using CSV, DataFrames, Statistics
using SeniSienna

val_dir = joinpath(@__DIR__, "..", "validation")
raw_dir = joinpath(@__DIR__, "..", "data", "raw")

sys, _ = build_seni_physical_system(raw_dir)
set_units_base_system!(sys, "NATURAL_UNITS")

# perfil horario del sistema (suma de la demanda canónica MODOM)
lt = CSV.read(joinpath(raw_dir, "processed", "loads_time_series",
                       "loads_time_series.csv"), DataFrame)
perfil = combine(groupby(lt, :time_block_order), :p_set_mw => sum => :mw)
sort!(perfil, :time_block_order)
demanda_h = perfil.mw
# el export físico corresponde al pico nocturno → factor relativo a su hora
factor_h = demanda_h ./ maximum(demanda_h)

loads = collect(get_components(PowerLoad, sys))
gens = collect(get_components(ThermalStandard, sys))
p0_load = Dict(get_name(l) => (get_active_power(l), get_reactive_power(l)) for l in loads)
p0_gen = Dict(get_name(g) => get_active_power(g) for g in gens)

vrows = NamedTuple[]
resumen = NamedTuple[]
for h in 1:24
    f = factor_h[h]
    for l in loads
        set_active_power!(l, p0_load[get_name(l)][1] * f)
        set_reactive_power!(l, p0_load[get_name(l)][2] * f)
    end
    for g in gens
        get_bus(g) |> get_bustype == ACBusTypes.REF && continue
        set_active_power!(g, p0_gen[get_name(g)] * f)
    end
    r = try
        solve_powerflow(ACPowerFlow(), sys)
    catch
        push!(resumen, (hora = h, convergio = false, v_min = NaN, v_max = NaN,
                        fuera_banda = -1))
        continue
    end
    vres = r["bus_results"]
    kvmap = Dict(get_number(b) => get_base_voltage(b) for b in get_components(ACBus, sys))
    alta = vres[[kvmap[n] >= 69.0 for n in vres.bus_number], :]
    push!(resumen, (hora = h, convergio = true,
                    v_min = round(minimum(alta.Vm); digits = 4),
                    v_max = round(maximum(alta.Vm); digits = 4),
                    fuera_banda = count((alta.Vm .< 0.95) .| (alta.Vm .> 1.05))))
    for rr in eachrow(alta)
        push!(vrows, (hora = h, bus = rr.bus_number, v_pu = rr.Vm))
    end
end

qd = DataFrame(resumen)
CSV.write(joinpath(val_dir, "fase4_qds_resumen.csv"), qd)
CSV.write(joinpath(val_dir, "fase4_qds_tensiones.csv"), DataFrame(vrows))
println("\n── Fase 4: cuasi-dinámico 24h ──")
show(qd; allrows = true, allcols = true)
println("\nHoras convergidas: ", count(qd.convergio), "/24")
