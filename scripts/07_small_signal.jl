# Fase 5 — Estabilidad de pequeña señal (PSID): eigenvalores, frecuencias y
# amortiguamientos del SENI con la capa dinámica v1 (máquinas reales del export,
# AVR/governor típicos). Comparación estructural contra el análisis modal de
# PowerFactory (referencia_small_signal.csv, 26 modos electromecánicos ζ<10%).

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerSimulationsDynamics
using CSV, DataFrames, Statistics
using SeniSienna

raw_dir = joinpath(@__DIR__, "..", "data", "raw")
val_dir = joinpath(@__DIR__, "..", "validation")

sys, _ = build_seni_physical_system(raw_dir)
attach_dynamic_models!(sys, raw_dir)

sim = Simulation(ResidualModel, sys, mktempdir(), (0.0, 1.0))
ss = small_signal_analysis(sim)
println("Pequeña señal: estable = ", ss.stable)

eig = ss.eigenvalues
rows = NamedTuple[]
for λ in eig
    f = abs(imag(λ)) / (2π)
    f < 1e-4 && continue                      # no oscilatorios
    ζ = -real(λ) / abs(λ)
    push!(rows, (parte_real = real(λ), parte_imag = imag(λ),
                 frecuencia_hz = f, amortiguamiento_pct = 100ζ))
end
modos = sort(DataFrame(rows), :amortiguamiento_pct)
CSV.write(joinpath(val_dir, "fase5_small_signal_sienna.csv"), modos)

em = modos[(modos.frecuencia_hz .> 0.1) .& (modos.frecuencia_hz .< 3.0), :]
println("\n── Fase 5: pequeña señal (Sienna, capa dinámica v1) ──")
println("  Eigenvalores totales: ", length(eig), "  (oscilatorios: ", nrow(modos), ")")
println("  Modos electromecánicos (0.1–3 Hz): ", nrow(em))
println("  ζ mínimo en banda EM: ", round(minimum(em.amortiguamiento_pct); digits = 2), " %")
println("  Modos EM con ζ < 10%: ", count(em.amortiguamiento_pct .< 10))

# referencia PowerFactory
ref = CSV.read(joinpath(raw_dir, "salida_dinamica_20260714",
                        "salida_dinamica_20260714_203429",
                        "referencia_small_signal.csv"), DataFrame)
ref_em = ref[(ref.tipo .== "oscilatorio") .& (ref.frecuencia_hz .> 0.1) .&
             (ref.frecuencia_hz .< 3.0), :]
println("\n  PowerFactory (referencia P20): modos EM = ", nrow(ref_em),
        ", con ζ < 10% = ", count(ref_em.amortiguamiento_pct .< 10),
        ", ζ mínimo = ", round(minimum(ref_em.amortiguamiento_pct); digits = 2), " %")
println("\nPeores 10 modos Sienna (banda EM):")
show(first(em, 10); allrows = true, allcols = true)
println()
