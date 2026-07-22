# Fase 3b — UC MILP completo con PowerSimulations (≙ Layer 2b de modom-pypsa +
# reservas, que allí quedaron pendientes): commitment binario, tiempos mínimos,
# rampas y reservas RPF/RSF co-optimizadas. Red tipo MODOM: transporte sin
# límites por rama (StaticBranchUnbounded) + flowgates (TransmissionInterface).
#
# Comparación vs MODOM: % de coincidencia de commitment, R² de despacho y costo.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerSimulations, HydroPowerSimulations, HiGHS
using CSV, DataFrames, Statistics, Dates, Logging
using SeniSienna

raw_dir = joinpath(@__DIR__, "..", "data", "raw")
val_dir = joinpath(@__DIR__, "..", "validation")

sys = System(joinpath(@__DIR__, "..", "data", "sys", "seni_dispatch.json"))
prune_to_main_island!(sys)

# ---- gap A · must-run --------------------------------------------------------
# Unidades que MODOM mantiene acopladas las 24 h (base de seguridad/tensión que
# el MILP puro no ve) → must_run=true, para no apagarlas. Sube la coincidencia
# de commitment.
modom_disp = CSV.read(joinpath(raw_dir, "processed", "modom_results",
                               "modom_generator_dispatch.csv"), DataFrame)
rename!(modom_disp, names(modom_disp)[1] => :snapshot)
Th = nrow(modom_disp)
n_mr = 0
for g in get_components(ThermalStandard, sys)
    gid = get_name(g)
    hasproperty(modom_disp, Symbol(gid)) || continue
    col = modom_disp[!, Symbol(gid)]
    if count(x -> !ismissing(x) && x > 1e-6, col) == Th   # ON en todas las horas
        set_must_run!(g, true); global n_mr += 1
    end
end
println("must-run aplicado a $n_mr unidades (siempre ON en MODOM)")

# PSI necesita pronósticos Deterministic: ventana única de 24 h
transform_single_time_series!(sys, Hour(24), Hour(24))

# ---- plantilla ------------------------------------------------------------------
template = ProblemTemplate(NetworkModel(PTDFPowerModel))
set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)
set_device_model!(template, PowerLoad, StaticPowerLoad)
set_device_model!(template, Line, StaticBranchUnbounded)
set_device_model!(template, Transformer2W, StaticBranchUnbounded)
set_service_model!(template, ServiceModel(VariableReserve{ReserveUp}, RangeReserve, "RPF"))
set_service_model!(template, ServiceModel(VariableReserve{ReserveUp}, RangeReserve, "RSF"))
set_service_model!(template, ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow))

problem = DecisionModel(template, sys;
    name = "UC_SENI",
    optimizer = optimizer_with_attributes(HiGHS.Optimizer,
        "mip_rel_gap" => 1e-3, "time_limit" => 300.0),
    horizon = Hour(24),
    optimizer_solve_log_print = false,
    store_variable_names = true)

out_dir = mktempdir()
build!(problem; console_level = Logging.Warn, output_dir = out_dir)
solve!(problem)

res = OptimizationProblemResults(problem)
pth = read_variable(res, "ActivePowerVariable__ThermalStandard")
on = read_variable(res, "OnVariable__ThermalStandard")
println("UC resuelto. Variables térmicas: ", size(pth))

# ---- comparación vs MODOM ---------------------------------------------------------
modom = CSV.read(joinpath(raw_dir, "processed", "modom_results",
                          "modom_generator_dispatch.csv"), DataFrame)
rename!(modom, names(modom)[1] => :snapshot)
T = nrow(modom)

rows = NamedTuple[]
for g in get_components(ThermalStandard, sys)
    gid = get_name(g)
    hasproperty(modom, Symbol(gid)) || continue
    gid in names(pth) || continue
    tiene_on = gid in names(on)   # las must_run NO tienen OnVariable (forzadas ON)
    for t in 1:T
        m_mw = coalesce(modom[t, Symbol(gid)], 0.0)
        s_on = tiene_on ? (on[t, gid] > 0.5) : true
        push!(rows, (gen = gid, hora = t, modom_mw = m_mw, sienna_mw = pth[t, gid],
                     modom_on = m_mw > 1e-6, sienna_on = s_on))
    end
end
cmp = DataFrame(rows)
match_uc = count(cmp.modom_on .== cmp.sienna_on)
tot_uc = nrow(cmp)
CSV.write(joinpath(val_dir, "fase3b_uc_comparison.csv"), cmp)

ss_res = sum((cmp.modom_mw .- cmp.sienna_mw) .^ 2)
ss_tot = sum((cmp.modom_mw .- mean(cmp.modom_mw)) .^ 2)
r2 = 1 - ss_res / ss_tot

# costo variable (CVP × MW) de ambos
cvp_of = Dict(get_name(g) =>
    get_proportional_term(get_value_curve(get_variable(get_operation_cost(g))))
    for g in get_components(ThermalStandard, sys))
costo_s = sum(get(cvp_of, r.gen, 0.0) * r.sienna_mw for r in eachrow(cmp))
costo_m = sum(get(cvp_of, r.gen, 0.0) * r.modom_mw for r in eachrow(cmp))

println("\n── Fase 3b: UC MILP (PSI) vs MODOM ──")
println("  Pares unidad-hora: ", nrow(cmp))
println("  Coincidencia de commitment: ", round(100 * match_uc / tot_uc; digits = 2), " %")
println("  R² de despacho: ", round(r2; digits = 4))
println("  Costo variable Sienna: ", round(costo_s / 1e6; digits = 2), " M\$")
println("  Costo variable MODOM:  ", round(costo_m / 1e6; digits = 2), " M\$")
println("  Desviación: ", round(100 * (costo_s - costo_m) / costo_m; digits = 2), " %")

# reservas asignadas
for svc in get_components(VariableReserve{ReserveUp}, sys)
    key = "ActivePowerReserveVariable__VariableReserve__ReserveUp__" * get_name(svc)
    try
        rsv = read_variable(res, key)
        println("  Reserva ", get_name(svc), ": media horaria = ",
                round(mean(sum(eachcol(rsv[!, 2:end]))); digits = 1), " MW")
    catch
        println("  Reserva ", get_name(svc), ": variable no encontrada (", key, ")")
    end
end
