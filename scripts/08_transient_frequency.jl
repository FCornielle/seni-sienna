# Fase 5 — Respuesta de frecuencia (PSID): pérdida de Punta Catalina 2 (~360 MW,
# el mismo evento del RMS de referencia de PowerFactory) → f(t) del COI y nadir.
# Referencia PF: nadir COI = 59.285 Hz. Criterio Código de Conexión: >= 59.2 Hz.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerSimulationsDynamics, Sundials
using CSV, DataFrames, Statistics
using SeniSienna

raw_dir = joinpath(@__DIR__, "..", "data", "raw")
val_dir = joinpath(@__DIR__, "..", "validation")

# generador a disparar: el nodo cuya lista de máquinas incluye Punta Catalina 2
function _find_gen(sys, patron)
    for g in get_components(ThermalStandard, sys)
        maqs = get(get_ext(g), "maquinas", NamedTuple[])
        any(m -> occursin(patron, m.loc_name), maqs) && return g
    end
    return nothing
end

# escalera de diagnóstico numérico sobre (AVR, governor)
function _run_trip(avr_mode, gov_mode)
    sys = first(build_seni_physical_system(raw_dir))
    attach_dynamic_models!(sys, raw_dir; avr_mode, gov_mode)
    objetivo = _find_gen(sys, "Punta Catalina 2")
    objetivo === nothing && error("No se encontró Punta Catalina 2")
    p_trip = get_active_power(objetivo)
    pert = GeneratorTrip(1.0, get_component(DynamicGenerator, sys, get_name(objetivo)))
    sim = Simulation(ResidualModel, sys, mktempdir(), (0.0, 30.0), pert)
    st = execute!(sim, IDA(linear_solver = :KLU); saveat = 0.02)
    return sys, objetivo, p_trip, st, sim
end

sys = nothing; objetivo = nothing; p_trip = 0.0; sim = nothing
modo_usado = (:ninguno, :ninguno)
for (am, gm) in ((:dsl, :dsl), (:sexs, :tipico), (:sexs, :sin_hygov), (:fixed, :fixed))
    global sys, objetivo, p_trip, sim, modo_usado
    s, o, p, st, sm = _run_trip(am, gm)
    println("avr = ", am, ", gov = ", gm, " → ", st)
    if occursin("FINALIZED", string(st))
        sys = s; objetivo = o; p_trip = p; sim = sm; modo_usado = (am, gm)
        break
    end
end
modo_usado == (:ninguno, :ninguno) && error("La simulación no completó en ninguna configuración")
println("Configuración usada: (avr, gov) = ", modo_usado)
println("Disparo: ", get_name(objetivo), " (", round(p_trip; digits = 1), " MW)")
res = read_results(sim)

# COI: Σ H·S·ω / Σ H·S (excluyendo la unidad disparada)
num = nothing; den = 0.0; tiempo = nothing
for dyn in get_components(DynamicGenerator, sys)
    get_name(dyn) == get_name(objetivo) && continue
    stat = get_component(ThermalStandard, sys, get_name(dyn))
    hs = get_H(get_shaft(dyn)) * get_base_power(stat)
    t, ω = get_state_series(res, (get_name(dyn), :ω))
    global tiempo = t
    global num = num === nothing ? hs .* ω : num .+ hs .* ω
    global den += hs
end
f_coi = 60.0 .* num ./ den
nadir = minimum(f_coi)
t_final = maximum(tiempo)
t_final < 29.0 && @warn "Simulación truncada" t_final

CSV.write(joinpath(val_dir, "fase5_rms_frecuencia_sienna.csv"),
          DataFrame(t_s = collect(tiempo), f_coi_hz = f_coi))

println("\n── Fase 5: respuesta de frecuencia (Sienna v1) ──")
println("  Evento: pérdida de ", round(p_trip; digits = 1), " MW en t=1 s")
println("  Nadir COI Sienna:       ", round(nadir; digits = 3), " Hz")
println("  Nadir COI PowerFactory: 59.285 Hz (referencia)")
println("  Frecuencia final (30 s): ", round(f_coi[end]; digits = 3), " Hz")
println("  Criterio Código de Conexión (>= 59.2 Hz): ",
        nadir >= 59.2 ? "CUMPLE" : "NO CUMPLE")
