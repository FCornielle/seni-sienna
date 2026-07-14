# Fase 1 — Construye el System del SENI desde data/raw/ y lo serializa a data/sys/.
# Requiere haber copiado los datos según data/raw/README.md.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems
using SeniSienna

raw_dir = joinpath(@__DIR__, "..", "data", "raw")
sys_dir = joinpath(@__DIR__, "..", "data", "sys")

sys = build_seni_system(raw_dir)
to_json(sys, joinpath(sys_dir, "seni_base.json"); force = true)
println("System serializado en data/sys/seni_base.json")
