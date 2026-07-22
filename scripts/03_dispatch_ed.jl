# Fase 3a — Despacho económico DC con commitment fijo de MODOM (≙ Layer 2a de
# modom-pypsa). Meta: R² >= 0.94 vs el despacho real de MODOM por unidad-hora.
#
# El commitment horario viene dado (unidad encendida ⟺ despacho MODOM > 0), por
# eso el LP se arma directo con JuMP sobre los datos del System PSY:
#   min Σ CVP·p + CENS·(ens + dump)
#   s.a. balance nodal DC (ángulos), límites de rama, flowgates,
#        pmin·commit <= p_térmico <= pmax·commit, hidro fija = MODOM,
#        0 <= p_renovable <= pronóstico
# (el UC binario completo es la Fase 3b con PowerSimulations, script 04)

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using PowerSystems, JuMP, HiGHS
using CSV, DataFrames, Statistics
using SeniSienna

const CENS = 2_000_000.0  # costo de ENS de MODOM (model_options.csv)

# MODOM es un modelo de transporte: NO impone límites térmicos por rama, solo
# los flowgates de seguridad N-1. Con límites por rama: ENS 7,898 MWh y R²
# 0.913; sin ellos: ENS 0 y R² 0.957 (validado empíricamente).
const ENFORCE_BRANCH_LIMITS = false

raw_dir = joinpath(@__DIR__, "..", "data", "raw")
val_dir = joinpath(@__DIR__, "..", "validation")

sys = System(joinpath(@__DIR__, "..", "data", "sys", "seni_dispatch.json"))
set_units_base_system!(sys, "NATURAL_UNITS")

# ---- despacho MODOM (referencia y commitment) --------------------------------
modom = CSV.read(joinpath(raw_dir, "processed", "modom_results",
                          "modom_generator_dispatch.csv"), DataFrame)
rename!(modom, names(modom)[1] => :snapshot)
T = nrow(modom)
gids = String.(names(modom)[2:end])
modom_mw = Dict{Tuple{String,Int},Float64}()
for (t, row) in enumerate(eachrow(modom)), g in gids
    modom_mw[(g, t)] = coalesce(row[Symbol(g)], 0.0)
end
committed(g, t) = get(modom_mw, (g, t), 0.0) > 1e-6

# ---- componentes del System ---------------------------------------------------
buses = collect(get_components(ACBus, sys))
busnum = Dict(get_name(b) => i for (i, b) in enumerate(buses))
nb = length(buses)

thermals = [g for g in get_components(ThermalStandard, sys) if get_available(g)]
hydros = [g for g in get_components(HydroDispatch, sys) if get_available(g)]
renews = [g for g in get_components(RenewableDispatch, sys) if get_available(g)]
loads = collect(get_components(PowerLoad, sys))

branches = vcat(collect(get_components(Line, sys)),
                collect(get_components(Transformer2W, sys)))
branches = [br for br in branches if get_available(br)]

cvp(g) = get_proportional_term(get_value_curve(get_variable(get_operation_cost(g))))
plim(g) = get_active_power_limits(g)  # MW (NATURAL_UNITS)

# series en MW
mwseries(c) = values(get_time_series_array(SingleTimeSeries, c, "max_active_power"))
demand = Dict(get_name(l) => mwseries(l) for l in loads)
ren_ub = Dict(get_name(g) => (has_time_series(g) ? mwseries(g) :
              fill(get_max_active_power(g), T)) for g in renews)

# ---- modelo -------------------------------------------------------------------
m = Model(HiGHS.Optimizer)
set_silent(m)

@variable(m, -2π <= θ[1:nb, 1:T] <= 2π)  # acotado: mata rayos en islas
@variable(m, pt[g in get_name.(thermals), 1:T] >= 0)
@variable(m, pr[g in get_name.(renews), 1:T] >= 0)
@variable(m, ens[1:nb, 1:T] >= 0)
@variable(m, dump[1:nb, 1:T] >= 0)
# gap A · pérdidas: carga extra por barra (0 en la 1ª pasada; se fija a las
# pérdidas DC computadas y se re-optimiza → lazo de pérdidas, eq. 29-30 MODOM)
@variable(m, loss_load[1:nb, 1:T] >= 0)
for b in 1:nb, t in 1:T; set_upper_bound(loss_load[b, t], 0.0); end

# térmicos: commitment fijo de MODOM
for g in thermals, t in 1:T
    lim = plim(g)
    if committed(get_name(g), t)
        set_upper_bound(pt[get_name(g), t], lim.max)
        set_lower_bound(pt[get_name(g), t], min(lim.min, lim.max))
    else
        set_upper_bound(pt[get_name(g), t], 0.0)
    end
end
# renovables: tope = pronóstico
for g in renews, t in 1:T
    set_upper_bound(pr[get_name(g), t], max(ren_ub[get_name(g)][t], 0.0))
end

# flujos DC por ángulos
flow = Dict{Tuple{String,Int},AffExpr}()
for br in branches, t in 1:T
    arc = get_arc(br)
    i, j = busnum[get_name(get_from(arc))], busnum[get_name(get_to(arc))]
    f = (θ[i, t] - θ[j, t]) / max(get_x(br), 1e-4)  # pu (mejor condicionamiento)
    flow[(get_name(br), t)] = f
    r = get_rating(br)
    if ENFORCE_BRANCH_LIMITS && r < 5_000
        @constraint(m, f <= r / 100.0)
        @constraint(m, f >= -r / 100.0)
    end
end

# balance nodal
inj = [AffExpr(0.0) for _ in 1:nb, _ in 1:T]
for g in thermals, t in 1:T
    add_to_expression!(inj[busnum[get_name(get_bus(g))], t], pt[get_name(g), t])
end
for g in renews, t in 1:T
    add_to_expression!(inj[busnum[get_name(get_bus(g))], t], pr[get_name(g), t])
end
for g in hydros, t in 1:T  # hidro fija = despacho MODOM (decisión de agua, no de costo)
    p = min(get(modom_mw, (get_name(g), t), 0.0), plim(g).max)
    add_to_expression!(inj[busnum[get_name(get_bus(g))], t], p)
end
for l in loads, t in 1:T
    add_to_expression!(inj[busnum[get_name(get_bus(l))], t], -demand[get_name(l)][t])
end
for b in 1:nb, t in 1:T           # pérdidas como carga extra por barra
    add_to_expression!(inj[b, t], -loss_load[b, t])
end
for (b, t) in Iterators.product(1:nb, 1:T)
    out = AffExpr(0.0)
    for br in branches
        arc = get_arc(br)
        i, j = busnum[get_name(get_from(arc))], busnum[get_name(get_to(arc))]
        i == b && add_to_expression!(out, flow[(get_name(br), t)])
        j == b && add_to_expression!(out, -flow[(get_name(br), t)])
    end
    @constraint(m, (inj[b, t] + ens[b, t] - dump[b, t]) / 100.0 == out)
end
@constraint(m, [t in 1:T], θ[1, t] == 0)  # referencia angular

# flowgates (TransmissionInterface)
for iface in get_components(TransmissionInterface, sys)
    lims = get_active_power_flow_limits(iface)
    dirs = get_direction_mapping(iface)
    members = [br for br in branches if iface in get_services(br)]
    isempty(members) && continue
    for t in 1:T
        expr = sum(get(dirs, get_name(br), 1) * flow[(get_name(br), t)] for br in members)
        @constraint(m, expr <= lims.max / 100.0)
        @constraint(m, expr >= lims.min / 100.0)
    end
end

# objetivo escalado 1e-3 (HiGHS: duales excesivos con CENS=2e6 sin escalar)
@objective(m, Min, 1e-3 * (
    sum(cvp(g) * pt[get_name(g), t] for g in thermals, t in 1:T) +
    CENS * sum(ens) + CENS * sum(dump)))

optimize!(m)
println("Estado: ", termination_status(m), " / ", raw_status(m))
if !has_values(m)
    error("El solver no devolvió solución: " * string(termination_status(m)))
end
println("ENS total: ", round(sum(value.(ens)); digits = 2), " MWh  Dump: ",
        round(sum(value.(dump)); digits = 2), " MWh")

# ---- lazo de pérdidas DC (eq. 29-30): P_perd_l = r_l · f_l² ; 50/50 a barras --
rl(br) = get_r(br)
costo_sin_perdidas = sum(cvp(g) * value(pt[get_name(g), t]) for g in thermals, t in 1:T)
for iter in 1:3
    perd_bus = zeros(nb, T)
    perd_tot = 0.0
    for br in branches, t in 1:T
        f = value(flow[(get_name(br), t)])          # pu
        p = rl(br) * f^2 * 100.0                     # MW
        arc = get_arc(br)
        perd_bus[busnum[get_name(get_from(arc))], t] += p / 2
        perd_bus[busnum[get_name(get_to(arc))], t] += p / 2
        perd_tot += p
    end
    for b in 1:nb, t in 1:T; set_upper_bound(loss_load[b, t], perd_bus[b, t]);
                             set_lower_bound(loss_load[b, t], perd_bus[b, t]); end
    optimize!(m)
    has_values(m) || (@warn "re-solve de pérdidas sin solución"; break)
    iter == 3 && println("Pérdidas DC (convergido): ", round(perd_tot; digits = 1),
                         " MW pico  (", round(100 * perd_tot / sum(sum(demand[get_name(l)]) for l in loads); digits = 2), "% aprox)")
end
costo_con_perdidas = sum(cvp(g) * value(pt[get_name(g), t]) for g in thermals, t in 1:T)
println("Costo variable  sin pérdidas: ", round(costo_sin_perdidas / 1e6; digits = 2),
        " M\$  →  con pérdidas: ", round(costo_con_perdidas / 1e6; digits = 2), " M\$")

# ---- mix de despacho por COMBUSTIBLE y hora (clasificación de modom-pypsa) ------
# classify_fuel portado de modom-pypsa/dashboard.py: por nombre de central + tech.
function _norm(s)
    n = uppercase(replace(string(s), r"[ÁÀÄ]"i => "A", r"[ÉÈË]"i => "E",
        r"[ÍÌÏ]"i => "I", r"[ÓÒÖ]"i => "O", r"[ÚÙÜ]"i => "U", "Ñ" => "N", "ñ" => "N"))
    return n
end
const _CARBON = ("PUNTA CATALINA", "BARAHONA CARBON")
const _WIND = ("LOS COCOS", "JUANCHO", "QUILVIO", "CABRERA", "GUANILLO", "MATAFONGO",
    "AGUA CLARA", "GUZMANCITO", "LARIMAR", "PECASA")
const _GAS = ("ESTRELLA DEL MAR", "SEABOARD", "LOS MINA", "SIBA", "MANZANILLO", "ENERGAS")
const _FUEL = ("POWERSHIP", "KPS", "SULTANA", "PIMENTEL", "PALAMARA", "LA VEGA", "BERSAL",
    "HAINA TG", "INCA", "METALDOM", "MONTE RIO", "SAN LORENZO", "PALENQUE",
    "LOS ORIGENES", "QUISQUEYA", "EDM", "CESPM")
const _HYDRO = ("JIGUEY", "AGUACATE", "VALDESIA", "TAVERA", "PALOMINO", "MONCION",
    "RIO BLANCO", "PINALITO", "HATILLO", "LOPEZ ANGOSTURA", "SABANA YEGUA",
    "SABANETA", "RINCON", "BAIGUAQUE", "ANIANA VARGAS", "DOMINGO RODRIGUEZ",
    "LAS DAMAS", "LAS BARIAS", "BRAZO DERECHO", "NIZAO", "NAJAYO", "MAGUEYAL",
    "JIMENOA", "EL SALTO", "CONTRAEMBALSE", "CONTRA EMBALSE", "LOS TOROS", "LOS ANONES")

function classify_fuel(name, tech)
    n = _norm(name); tg = strip(string(tech))
    has(ws) = any(w -> occursin(w, n), ws)
    (occursin("ITABO", n) && !occursin("TG", n)) && return "Carbón"
    has(_CARBON) && return "Carbón"
    occursin(r"SOLAR|FOTOVOLT|\bFV\b|\bPV\b", n) && return "Solar"
    (occursin(r"EOLIC|VIENTO|\bWIND\b", n) || has(_WIND)) && return "Eólica"
    occursin(r"BIO|INGENIO|BAGAZO", n) && return "Biomasa"
    (tg in ("2", "3") || has(_HYDRO)) && return "Hidro"
    (occursin(r"\bGN\b|GAS NATURAL|CICLO COMBINADO|\bCC\b", n) || has(_GAS)) && return "Gas Natural"
    (occursin(r"\bFO\b|FUEL|VAPOR|DIESEL|MOTOR|GASOIL", n) || has(_FUEL)) && return "Fuel Oil / Diesel"
    return "Otra"
end

gens_meta = CSV.read(joinpath(raw_dir, "processed", "generators", "generators.csv"), DataFrame)
nombre_de = Dict(String(r.generator_id) => String(r.generator_name) for r in eachrow(gens_meta))
fuel_de = Dict(String(r.generator_id) =>
               classify_fuel(r.generator_name, r.technology_group) for r in eachrow(gens_meta))
_fuel(gid) = get(fuel_de, gid, "Otra")

const FUELS = ["Carbón", "Fuel Oil / Diesel", "Gas Natural", "Biomasa", "Hidro", "Eólica", "Solar", "Otra"]
fuel_rows = NamedTuple[]
for t in 1:T
    mw = Dict(f => 0.0 for f in FUELS)
    for g in thermals; mw[_fuel(get_name(g))] += value(pt[get_name(g), t]); end
    for g in hydros; mw[_fuel(get_name(g))] += min(get(modom_mw, (get_name(g), t), 0.0), plim(g).max); end
    for g in renews; mw[_fuel(get_name(g))] += value(pr[get_name(g), t]); end
    dem = sum(demand[get_name(l)][t] for l in loads; init = 0.0)
    push!(fuel_rows, (; hora = t, (Symbol(f) => round(mw[f]; digits = 1) for f in FUELS)...,
                      demanda = round(dem; digits = 1)))
end
CSV.write(joinpath(val_dir, "despacho_fuel_hora.csv"), DataFrame(fuel_rows))
println("Mix por combustible×hora → validation/despacho_fuel_hora.csv")

# despacho térmico por unidad, con NOMBRE de central (para el gráfico por planta)
und_rows = NamedTuple[]
for g in thermals, t in 1:T
    gid = get_name(g); p = value(pt[gid, t])
    push!(und_rows, (hora = t, gen = gid, nombre = get(nombre_de, gid, gid),
                     mw = round(p; digits = 1)))
end
CSV.write(joinpath(val_dir, "despacho_unidad_hora.csv"), DataFrame(und_rows))
println("Despacho por unidad (con nombre) → validation/despacho_unidad_hora.csv")

# ---- ENS por barra vs ENS de MODOM ---------------------------------------------
modom_ens = CSV.read(joinpath(raw_dir, "processed", "modom_results",
                              "modom_bus_ens.csv"), DataFrame; header = 1)
ens_modom_bus = Dict{String,Float64}()
for c in names(modom_ens)[2:end]
    ens_modom_bus[String(c)] = sum(skipmissing(modom_ens[!, c]))
end
ens_rows = [(bus = get_name(buses[b]), ens_sienna = sum(value(ens[b, t]) for t in 1:T),
             ens_modom = get(ens_modom_bus, get_name(buses[b]), 0.0)) for b in 1:nb]
ens_df = DataFrame(ens_rows)
ens_df.exceso = ens_df.ens_sienna .- ens_df.ens_modom
CSV.write(joinpath(val_dir, "fase3_ens_por_barra.csv"), sort(ens_df, :exceso, rev = true))
println("ENS MODOM total: ", round(sum(values(ens_modom_bus)); digits = 1),
        " MWh — top 10 exceso nuestro:")
show(first(sort(ens_df[ens_df.exceso .> 1, :], :exceso, rev = true), 10);
     allrows = true, allcols = true)
println()

# ---- comparación vs MODOM -------------------------------------------------------
rows = NamedTuple[]
for g in thermals, t in 1:T
    gid = get_name(g)
    haskey(modom_mw, (gid, t)) || continue
    push!(rows, (gen = gid, hora = t, tipo = "termico",
                 modom = modom_mw[(gid, t)], sienna = value(pt[gid, t])))
end
cmp = DataFrame(rows)
CSV.write(joinpath(val_dir, "fase3_dispatch_comparison.csv"), cmp)

ss_res = sum((cmp.modom .- cmp.sienna) .^ 2)
ss_tot = sum((cmp.modom .- mean(cmp.modom)) .^ 2)
r2 = 1 - ss_res / ss_tot
costo = sum(cvp(g) * value(pt[get_name(g), t]) for g in thermals, t in 1:T)
costo_modom = sum(cvp(g) * modom_mw[(get_name(g), t)] for g in thermals, t in 1:T
                  if haskey(modom_mw, (get_name(g), t)))

println("\n── Fase 3a: ED con commitment fijo vs MODOM ──")
println("  Pares unidad-hora (térmicos): ", nrow(cmp))
println("  R² térmicos: ", round(r2; digits = 4))
println("  Costo variable Sienna: ", round(costo / 1e6; digits = 2), " M\$")
println("  Costo variable MODOM:  ", round(costo_modom / 1e6; digits = 2), " M\$")
println("  Desviación de costo: ",
        round(100 * (costo - costo_modom) / costo_modom; digits = 2), " %")
