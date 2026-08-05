# Fase 2 AC por escenario (P01–P24): resuelve el flujo AC del System físico para
# cada punto de operación de PowerFactory (op_*_P01_P24, Ronda 2) y compara las
# tensiones contra la referencia de PF por escenario (tensiones_P01_P24, Ronda 3).
# Extiende la Fase 2 (hoy solo P20) a los 24 escenarios.
#
#   julia --project=. scripts/17_fase2_por_escenario.jl [P01 P05 ...]   (default: todos)

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, PowerFlows, CSV, DataFrames, Statistics
using SeniSienna

raw_dir = joinpath(@__DIR__, "..", "data", "raw")
val_dir = joinpath(@__DIR__, "..", "validation")
op_dir_long = joinpath(raw_dir, "salida_op_P01_P24_20260804_191945")
ten_dir = joinpath(raw_dir, "salida_tensiones_P01_P24_20260805_115455")
p20_taps = joinpath(raw_dir, "salida_bloqueI_edac_20260717_111009", "escenario_P20_taps.csv")

# ---- flujo AC con control secundario + límites Q (idéntico a script 02) -------
function solve_with_controls!(sys, spec; max_iter = 25, k = 0.7)
    num2bus = Dict(get_number(b) => b for b in get_components(ACBus, sys))
    bus_by_name = Dict(get_name(b) => b for b in get_components(ACBus, sys))
    gens_by_bus = Dict(get_name(get_bus(g)) => g for g in get_components(ThermalStandard, sys))
    res = nothing
    for it in 1:max_iter
        res = solve_powerflow(ACPowerFlow(), sys)
        br = res["bus_results"]
        qcol = first(c for c in names(br) if occursin("Q_gen", string(c)))
        v_by_num = Dict(r.bus_number => r.Vm for r in eachrow(br))
        max_err = 0.0
        for sc in spec
            pb = bus_by_name[sc.pilot_bus]
            err = sc.vset - v_by_num[get_number(pb)]
            max_err = max(max_err, abs(err))
            abs(err) < 0.001 && continue
            for mb in sc.member_buses
                b = bus_by_name[mb]
                get_bustype(b) == ACBusTypes.PV || continue
                set_magnitude!(b, clamp(get_magnitude(b) + k * err, 0.95, 1.1))
            end
        end
        conmutados = 0
        for r in eachrow(br)
            bus = num2bus[r.bus_number]
            get_bustype(bus) == ACBusTypes.PV || continue
            g = get(gens_by_bus, get_name(bus), nothing); g === nothing && continue
            lim = get_reactive_power_limits(g); q = r[qcol]
            if q > lim.max + 0.5
                set_reactive_power!(g, lim.max); set_bustype!(bus, ACBusTypes.PQ); conmutados += 1
            elseif q < lim.min - 0.5
                set_reactive_power!(g, lim.min); set_bustype!(bus, ACBusTypes.PQ); conmutados += 1
            end
        end
        (conmutados == 0 && max_err < 0.001) && break
    end
    return res
end

# ---- datos: op points largos + referencia + mapa for_name→ruta (taps) --------
cargas = CSV.read(joinpath(op_dir_long, "op_cargas_P01_P24.csv"), DataFrame)
gener = CSV.read(joinpath(op_dir_long, "op_generacion_P01_P24.csv"), DataFrame)
taps = CSV.read(joinpath(op_dir_long, "op_taps_P01_P24.csv"), DataFrame)
ten = CSV.read(joinpath(ten_dir, "tensiones_P01_P24.csv"), DataFrame)
fn2ruta = Dict(string(r.for_name) => string(r.ruta)
               for r in eachrow(CSV.read(p20_taps, DataFrame)) if !ismissing(r.for_name))

escenarios = length(ARGS) >= 1 ? ARGS : ["P$(lpad(i,2,'0'))" for i in 1:24]
resumen = NamedTuple[]

for esc in escenarios
    println("\n── $esc ──")
    tmp = mktempdir()
    # cargas y generación: subconjunto del escenario (mismas columnas que P20)
    CSV.write(joinpath(tmp, "escenario_P20_cargas.csv"),
              select(cargas[cargas.escenario .== esc, :], Not(:escenario)))
    CSV.write(joinpath(tmp, "escenario_P20_generacion.csv"),
              select(gener[gener.escenario .== esc, :], Not(:escenario)))
    # taps: añadir columna ruta (mapeada por for_name) para el match de _apply_op_point!
    tp = select(taps[taps.escenario .== esc, :], Not(:escenario))
    tp.ruta = [get(fn2ruta, string(fn), "") for fn in tp.for_name]
    CSV.write(joinpath(tmp, "escenario_P20_taps.csv"), tp)

    local sys, forname_to_bus, spec, res
    try
        sys, forname_to_bus, spec = build_seni_physical_system(raw_dir; op_dir = tmp)
        set_units_base_system!(sys, "NATURAL_UNITS")
        res = solve_with_controls!(sys, spec)
    catch e
        println("  ✗ $esc falló: ", sprint(showerror, e)[1:min(end, 160)]); continue
    end
    bus_res = res["bus_results"]
    name_by_num = Dict(get_number(b) => get_name(b) for b in get_components(ACBus, sys))
    kv_by_num = Dict(get_number(b) => get_base_voltage(b) for b in get_components(ACBus, sys))
    v_by_bus = Dict(name_by_num[r.bus_number] => r.Vm for r in eachrow(bus_res))
    kv_by_bus = Dict(name_by_num[r.bus_number] => kv_by_num[r.bus_number] for r in eachrow(bus_res))

    # referencia PF del escenario: por for_name W, energizada
    ref = ten[(ten.escenario .== esc), :]
    ref = ref[.!ismissing.(ref.for_name) .&& startswith.(coalesce.(string.(ref.for_name), ""), "W") .&&
              (ref.energizada .== 1), :]
    refv = combine(groupby(ref, :for_name), :V_pu => mean => :vpf)
    dvs = Float64[]; dvs_alta = Float64[]
    for r in eachrow(refv)
        fn = string(r.for_name)
        haskey(forname_to_bus, fn) || continue
        bn = forname_to_bus[fn]; haskey(v_by_bus, bn) || continue
        dv = abs(v_by_bus[bn] - r.vpf); push!(dvs, dv)
        get(kv_by_bus, bn, 0.0) >= 69.0 && push!(dvs_alta, dv)
    end
    isempty(dvs_alta) && (println("  sin barras cruzadas"); continue)
    row = (escenario = esc, barras = length(dvs_alta),
           dv_medio = round(mean(dvs_alta); digits = 5), dv_max = round(maximum(dvs_alta); digits = 5),
           dentro_0005 = count(<(0.005), dvs_alta))
    push!(resumen, row)
    println("  |ΔV|≥69kV: medio ", row.dv_medio, " máx ", row.dv_max,
            "  (", row.barras, " barras, ", row.dentro_0005, " < 0.005)")
end

df = DataFrame(resumen)
CSV.write(joinpath(val_dir, "fase2_p01_p24.csv"), df)
println("\n── Fase 2 AC por escenario ──")
show(df; allrows = true, allcols = true)
if nrow(df) > 0
    println("\n  |ΔV| medio global: ", round(mean(df.dv_medio); digits = 5),
            " pu · máx global: ", round(maximum(df.dv_max); digits = 5),
            " · escenarios: ", nrow(df))
end
println("\n✓ validation/fase2_p01_p24.csv")
