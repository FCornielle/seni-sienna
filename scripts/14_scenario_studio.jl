# Scenario Studio — UC MILP con perillas de escenario (≙ Scenario Studio de la
# webapp de modom-pypsa). Lee data/scenario_overrides.json (demanda, CVP,
# unidades fuera, % de reserva), construye el System con esos overrides, corre
# el UC y reporta métricas con su delta contra la línea base.
#
#   julia --project=. scripts/14_scenario_studio.jl
#
# La línea base (overrides identidad) se cachea en validation/scenario_baseline.json
# la primera vez; el resultado del escenario va a validation/scenario_result.json.

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerSimulations, HydroPowerSimulations, HiGHS
using CSV, DataFrames, Statistics, Dates, Logging, JSON3, Plots
using SeniSienna

raw_dir = joinpath(@__DIR__, "..", "data", "raw")
val_dir = joinpath(@__DIR__, "..", "validation")
ov_file = joinpath(@__DIR__, "..", "data", "scenario_overrides.json")

es_identidad(ov) = ov === nothing ||
    (Float64(get(ov, :demand_scale, 1.0)) == 1.0 &&
     isempty(get(ov, :cvp_mult, Dict())) &&
     isempty(get(ov, :gen_disabled, [])) &&
     Float64(get(ov, :reserve_pct, 0.03)) == 0.03)

# ---- correr el UC y devolver métricas ----------------------------------------
function correr_uc(; overrides_file)
    sys = build_seni_dispatch_system(raw_dir; overrides_file)
    prune_to_main_island!(sys)
    transform_single_time_series!(sys, Hour(24), Hour(24))

    template = ProblemTemplate(NetworkModel(PTDFPowerModel))
    set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)
    set_device_model!(template, PowerLoad, StaticPowerLoad)
    set_device_model!(template, Line, StaticBranchUnbounded)
    set_device_model!(template, Transformer2W, StaticBranchUnbounded)
    set_service_model!(template, ServiceModel(VariableReserve{ReserveUp}, RangeReserve, "RPF"))
    set_service_model!(template, ServiceModel(VariableReserve{ReserveUp}, RangeReserve, "RSF_AGC"))
    set_service_model!(template, ServiceModel(TransmissionInterface, ConstantMaxInterfaceFlow))

    problem = DecisionModel(template, sys; name = "UC_ESC",
        optimizer = optimizer_with_attributes(HiGHS.Optimizer,
            "mip_rel_gap" => 1e-3, "time_limit" => 300.0),
        horizon = Hour(24), store_variable_names = true)
    build!(problem; console_level = Logging.Error, output_dir = mktempdir())
    solve!(problem)
    res = OptimizationProblemResults(problem)
    pth = read_variable(res, "ActivePowerVariable__ThermalStandard")
    on = read_variable(res, "OnVariable__ThermalStandard")

    cvp_of = Dict(get_name(g) =>
        get_proportional_term(get_value_curve(get_variable(get_operation_cost(g))))
        for g in get_components(ThermalStandard, sys))
    gens = [c for c in names(pth) if c != "DateTime"]
    T = nrow(pth)
    costo = sum(get(cvp_of, g, 0.0) * pth[h, g] for g in gens, h in 1:T)
    gen_termica = sum(pth[h, g] for g in gens, h in 1:T)
    comprometidas = sum(on[h, g] > 0.5 for g in gens, h in 1:T)
    curva = [sum(pth[h, g] for g in gens) for h in 1:T]
    return (costo_MUSD = costo / 1e6, gen_termica_GWh = gen_termica / 1e3,
            unidad_horas_on = comprometidas, curva_termica = curva)
end

# ---- línea base (identidad, cacheada) ----------------------------------------
base_file = joinpath(val_dir, "scenario_baseline.json")
baseline = if isfile(base_file)
    JSON3.read(read(base_file, String))
else
    println("Generando línea base (overrides identidad)...")
    b = correr_uc(; overrides_file = joinpath(mktempdir(), "vacio.json"))  # no existe → identidad
    open(base_file, "w") do io; JSON3.write(io, b); end
    b
end

# ---- escenario actual ---------------------------------------------------------
ov = isfile(ov_file) ? JSON3.read(read(ov_file, String)) : nothing
if es_identidad(ov)
    println("Sin overrides activos → el escenario ES la línea base.")
    esc = baseline
else
    println("Corriendo escenario con overrides: ", ov)
    esc = correr_uc(; overrides_file = ov_file)
end

# ---- delta + salidas ----------------------------------------------------------
Δ(a, b) = round(100 * (a - b) / b; digits = 2)
resumen = DataFrame(
    metrica = ["Costo variable (M\$)", "Generación térmica (GWh)", "Unidad-horas ON"],
    base = round.([baseline.costo_MUSD, baseline.gen_termica_GWh,
                   Float64(baseline.unidad_horas_on)]; digits = 2),
    escenario = round.([esc.costo_MUSD, esc.gen_termica_GWh,
                        Float64(esc.unidad_horas_on)]; digits = 2),
    delta_pct = [Δ(esc.costo_MUSD, baseline.costo_MUSD),
                 Δ(esc.gen_termica_GWh, baseline.gen_termica_GWh),
                 Δ(Float64(esc.unidad_horas_on), Float64(baseline.unidad_horas_on))])
CSV.write(joinpath(val_dir, "scenario_resumen.csv"), resumen)
open(joinpath(val_dir, "scenario_result.json"), "w") do io
    JSON3.write(io, (overrides = ov, baseline = baseline, escenario = esc))
end

const C1 = RGB(0.45, 0.5, 0.55); const C2 = RGB(0.255, 0.412, 0.882)
p = plot(1:length(baseline.curva_termica), collect(baseline.curva_termica);
         color = C1, lw = 2, ls = :dash, label = "base",
         xlabel = "Hora", ylabel = "Generación térmica (MW)",
         title = "Scenario Studio — despacho térmico horario", size = (900, 460))
plot!(p, 1:length(esc.curva_termica), collect(esc.curva_termica);
      color = C2, lw = 2.5, label = "escenario")
savefig(p, joinpath(val_dir, "figuras", "f8_scenario_studio.png"))

println("\n── Scenario Studio ──")
show(resumen; allrows = true, allcols = true)
println()
