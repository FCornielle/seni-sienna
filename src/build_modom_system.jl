# Fase 1 — System de despacho del SENI desde las tablas canónicas MODOM
# (data/raw/processed/), equivalente a la red PyPSA de modom-pypsa (Layer 2).
# El System de red física del export PowerFactory (Fase 2) se construye aparte.
#
# Convenciones de los datos canónicos:
#  - r_pu / x_pu ya están en pu del sistema (SBASE = 100 MVA, model_options.csv)
#  - Demanda: loads_time_series.csv en formato largo (load_id = bus, h_01..h_24, MW)
#  - Renovables: renewable_profiles.csv con forecast_pu relativo a static_pmax_mw
#  - Hidro: generator_availability.csv con available_pu relativo a static_pmax_mw
#  - Flowgates: flowgate_limits.csv (por snapshot) + flowgate_members.csv

const MODOM_SBASE = 100.0

_read_csv(parts...) = CSV.read(joinpath(parts...), DataFrame)

_bool(x::Bool) = x
_bool(x) = lowercase(strip(string(x))) in ("true", "1", "1.0")

_num(x, default) = (x === missing || x === nothing) ? default : Float64(x)

function load_modom_tables(processed::AbstractString)
    return Dict{String,DataFrame}(
        "buses"         => _read_csv(processed, "buses", "buses.csv"),
        "generators"    => _read_csv(processed, "generators", "generators.csv"),
        "gen_params"    => _read_csv(processed, "commitment", "gen_params.csv"),
        "branches"      => _read_csv(processed, "branches", "branches.csv"),
        "loads"         => _read_csv(processed, "loads_time_series", "loads_time_series.csv"),
        "renewables"    => _read_csv(processed, "renewable_profiles", "renewable_profiles.csv"),
        "availability"  => _read_csv(processed, "generator_availability", "generator_availability.csv"),
        "snapshots"     => _read_csv(processed, "snapshots", "snapshots.csv"),
        "fg_limits"     => _read_csv(processed, "flowgates", "flowgate_limits.csv"),
        "fg_members"    => _read_csv(processed, "flowgates", "flowgate_members.csv"),
        "gen_reservoir" => _read_csv(processed, "hydro", "gen_reservoir.csv"),
        "modom_flows"   => _read_csv(processed, "modom_results", "modom_branch_flows.csv"),
    )
end

"Ramas con flujo distinto de cero en la solución MODOM (red efectiva)."
function _branches_with_modom_flow(t)::Set{String}
    flows = t["modom_flows"]
    activos = Set{String}()
    cols = Set(String.(names(flows)))
    for row in eachrow(t["branches"])
        cc = replace(String(row.circuit_id), r"^[LT]" => "c")
        for col in (String(row.from_bus) * "|" * String(row.to_bus) * "|" * cc,
                    String(row.to_bus) * "|" * String(row.from_bus) * "|" * cc)
            if col in cols && maximum(abs, skipmissing(flows[!, col]); init = 0.0) > 0.01
                push!(activos, String(row.branch_id))
                break
            end
        end
    end
    return activos
end

"""
    build_seni_dispatch_system(raw_dir; first_timestamp) -> System

Construye el System de despacho del SENI (717 barras) desde
`raw_dir/processed/` y adjunta las series horarias de demanda,
renovables e hidro. Los flowgates quedan como TransmissionInterface.
"""
function build_seni_dispatch_system(
    raw_dir::AbstractString;
    first_timestamp::DateTime = DateTime(2026, 6, 11),
)
    t = load_modom_tables(joinpath(raw_dir, "processed"))
    n_hours = nrow(t["snapshots"])
    timestamps = range(first_timestamp; step = Hour(1), length = n_hours)

    sys = System(MODOM_SBASE)

    _add_buses!(sys, t)
    stats = Dict{String,Int}()
    _add_branches!(sys, t, stats)
    _add_generators!(sys, t, timestamps, stats)
    _add_loads!(sys, t, timestamps, stats)
    _add_flowgates!(sys, t, stats)
    _reconnect_deficient_islands!(sys, t, stats)
    _set_reference_bus!(sys, t)

    _report(sys, t, stats)
    return sys
end

# ---------------------------------------------------------------- barras ----

function _add_buses!(sys::System, t)
    for (i, row) in enumerate(eachrow(t["buses"]))
        bus = ACBus(;
            number = i,
            name = String(row.bus_id_modom),
            bustype = ACBusTypes.PQ,
            angle = 0.0,
            magnitude = 1.0,
            voltage_limits = (min = 0.95, max = 1.05),
            base_voltage = _num(row.v_nom_kv, 138.0),
        )
        add_component!(sys, bus)
    end
end

# ----------------------------------------------------------------- ramas ----

function _add_branches!(sys::System, t, stats)
    arcs = Dict{Tuple{String,String},Arc}()
    stats["lineas"] = 0; stats["trafos"] = 0; stats["ramas_omitidas"] = 0
    stats["ramas_por_flujo"] = 0
    # la red EFECTIVA de MODOM incluye ramas marcadas fuera de servicio en el
    # caso base pero con flujo real en su solución (19 detectadas)
    con_flujo = _branches_with_modom_flow(t)
    for row in eachrow(t["branches"])
        forzada = String(row.branch_id) in con_flujo
        if !_bool(row.pypsa_v1_include) && !forzada
            stats["ramas_omitidas"] += 1
            continue
        end
        forzada && !_bool(row.pypsa_v1_include) && (stats["ramas_por_flujo"] += 1)
        fb = get_component(ACBus, sys, String(row.from_bus))
        tb = get_component(ACBus, sys, String(row.to_bus))
        if fb === nothing || tb === nothing || row.from_bus == row.to_bus
            stats["ramas_omitidas"] += 1
            continue
        end
        arc = get!(arcs, (String(row.from_bus), String(row.to_bus))) do
            a = Arc(fb, tb)
            add_component!(sys, a)
            a
        end
        r = max(_num(row.r_pu, 0.0), 0.0)
        x = max(abs(_num(row.x_pu, 1e-4)), 1e-5)  # evita PTDF singular
        # rating en pu del sistema; fmax <= 0 o centinela grande = sin límite
        fmax = _num(row.fmax_mw, 0.0)
        rating = (fmax > 0 && fmax < 5_000) ? fmax / MODOM_SBASE : 99.99
        available = string(row.operational_status) == "closed" || forzada
        name = String(row.branch_id)
        # PSY no admite Line entre tensiones distintas (v_nom inferida en la
        # capa canónica) → esas ramas se modelan como Transformer2W
        mixed_kv = get_base_voltage(fb) != get_base_voltage(tb)
        if string(row.branch_type) == "transformer" || mixed_kv
            add_component!(sys, Transformer2W(;
                name, available,
                active_power_flow = 0.0, reactive_power_flow = 0.0,
                arc, r, x, primary_shunt = 0.0, rating,
            ))
            stats["trafos"] += 1
        else
            add_component!(sys, Line(;
                name, available,
                active_power_flow = 0.0, reactive_power_flow = 0.0,
                arc, r, x, b = (from = 0.0, to = 0.0), rating,
                angle_limits = (min = -π / 2, max = π / 2),
            ))
            stats["lineas"] += 1
        end
    end
end

# ------------------------------------------------------------ generadores ----

# Clasificación por datos:
#  - con perfil en renewable_profiles.csv         → RenewableDispatch
#  - technology_group 4 o con embalse asociado    → HydroDispatch
#  - resto                                        → ThermalStandard
function _add_generators!(sys::System, t, timestamps, stats)
    renew_ids = Set(String.(t["renewables"].generator_id))
    hydro_ids = Set(String.(t["gen_reservoir"].generator_id))
    params = Dict(String(r.generator_id) => r for r in eachrow(t["gen_params"]))

    renew_profiles = _pivot_series(t["renewables"], :generator_id, :forecast_pu)
    avail_profiles = _pivot_series(t["availability"], :generator_id, :available_pu)

    stats["termicos"] = 0; stats["hidro"] = 0; stats["renovables"] = 0
    stats["gens_omitidos"] = 0

    for row in eachrow(t["generators"])
        gid = String(row.generator_id)
        bus = get_component(ACBus, sys, String(row.bus_id))
        if bus === nothing
            stats["gens_omitidos"] += 1
            continue
        end
        pmax = _num(row.effective_pmax_mw, 0.0)
        pmin = clamp(_num(row.effective_pmin_mw, 0.0), 0.0, pmax)
        base = max(pmax, 1.0)
        available = _num(row.enabled_flag, 1.0) == 1.0
        tech = strip(string(row.technology_group))
        bus.bustype == ACBusTypes.PQ && set_bustype!(bus, ACBusTypes.PV)

        if gid in renew_ids
            gen = RenewableDispatch(;
                name = gid, available, bus,
                active_power = 0.0, reactive_power = 0.0,
                rating = 1.0,
                prime_mover_type = tech == "2" ? PrimeMovers.WT : PrimeMovers.PVe,
                reactive_power_limits = (min = 0.0, max = 0.0),
                power_factor = 1.0,
                operation_cost = RenewableGenerationCost(CostCurve(LinearCurve(0.0))),
                base_power = base,
            )
            add_component!(sys, gen)
            _attach_profile!(sys, gen, renew_profiles, gid, timestamps)
            stats["renovables"] += 1
        elseif tech == "4" || gid in hydro_ids
            gen = HydroDispatch(;
                name = gid, available, bus,
                active_power = 0.0, reactive_power = 0.0,
                rating = 1.0,
                prime_mover_type = PrimeMovers.HY,
                active_power_limits = (min = 0.0, max = pmax / base),
                reactive_power_limits = (min = -0.3, max = 0.3),
                ramp_limits = nothing, time_limits = nothing,
                base_power = base,
                operation_cost = HydroGenerationCost(;
                    variable = CostCurve(LinearCurve(0.0)), fixed = 0.0),
            )
            add_component!(sys, gen)
            # disponibilidad horaria MODOM = techo de despacho hidro
            _attach_profile!(sys, gen, avail_profiles, gid, timestamps)
            stats["hidro"] += 1
        else
            p = get(params, gid, nothing)
            # Supuesto: RS/RB de MODOM en MW/h → pu(base propia)/min
            ramp = if p !== nothing && _num(p.RS, 0.0) > 0 && _num(p.RB, 0.0) > 0
                (up = _num(p.RS, 0.0) / 60 / base, down = _num(p.RB, 0.0) / 60 / base)
            else
                nothing
            end
            gen = ThermalStandard(;
                name = gid, available, status = true, bus,
                active_power = 0.0, reactive_power = 0.0,
                rating = 1.0,
                active_power_limits = (min = pmin / base, max = pmax / base),
                reactive_power_limits = (min = -0.4, max = 0.4),
                ramp_limits = ramp,
                operation_cost = ThermalGenerationCost(;
                    variable = CostCurve(LinearCurve(_num(row.effective_cvp, 0.0))),
                    fixed = 0.0, start_up = 0.0, shut_down = 0.0),
                base_power = base,
                time_limits = nothing,
                prime_mover_type = PrimeMovers.OT,
                fuel = ThermalFuels.OTHER,
            )
            add_component!(sys, gen)
            stats["termicos"] += 1
        end
    end
end

"Pivotea una tabla larga (id, orden, valor) a Dict id → vector 24h."
function _pivot_series(df::DataFrame, idcol::Symbol, valcol::Symbol;
                       ordercol::Symbol = :snapshot_order)
    out = Dict{String,Vector{Float64}}()
    for g in groupby(df, idcol)
        sorted = sort(g, ordercol)
        out[String(first(sorted[!, idcol]))] = [_num(v, 0.0) for v in sorted[!, valcol]]
    end
    return out
end

function _attach_profile!(sys, comp, profiles, gid, timestamps)
    haskey(profiles, gid) || return
    vals = clamp.(profiles[gid], 0.0, 1.0)
    ts = SingleTimeSeries(
        "max_active_power",
        TimeArray(collect(timestamps), vals);
        scaling_factor_multiplier = get_max_active_power,
    )
    add_time_series!(sys, comp, ts)
end

# ---------------------------------------------------------------- cargas ----

function _add_loads!(sys::System, t, timestamps, stats)
    profiles = _pivot_series(t["loads"], :load_id, :p_set_mw; ordercol = :time_block_order)
    stats["cargas"] = 0; stats["cargas_omitidas"] = 0
    for (bus_id, mw) in profiles
        bus = get_component(ACBus, sys, bus_id)
        if bus === nothing
            stats["cargas_omitidas"] += 1
            continue
        end
        peak = max(maximum(mw), 1e-6)
        load = PowerLoad(;
            name = "load_" * bus_id, available = true, bus,
            active_power = peak / MODOM_SBASE, reactive_power = 0.0,
            base_power = MODOM_SBASE,
            max_active_power = peak / MODOM_SBASE, max_reactive_power = 0.0,
        )
        add_component!(sys, load)
        ts = SingleTimeSeries(
            "max_active_power",
            TimeArray(collect(timestamps), mw ./ peak);
            scaling_factor_multiplier = get_max_active_power,
        )
        add_time_series!(sys, load, ts)
        stats["cargas"] += 1
    end
end

# -------------------------------------------------------------- flowgates ----

function _add_flowgates!(sys::System, t, stats)
    stats["flowgates"] = 0
    lims = combine(groupby(t["fg_limits"], :flowgate_id), :fmax_mw => minimum => :fmax)
    for row in eachrow(lims)
        members = t["fg_members"][t["fg_members"].flowgate_id .== row.flowgate_id, :]
        branches = ACBranch[]
        dirs = Dict{String,Int}()
        for m in eachrow(members)
            name = String(m.branch_name)
            br = get_component(Line, sys, name)
            br === nothing && (br = get_component(Transformer2W, sys, name))
            br === nothing && continue
            push!(branches, br)
            dirs[name] = Int(_num(m.orient, 1.0)) * Int(sign(_num(m.coefficient, 1.0)))
        end
        isempty(branches) && continue
        iface = TransmissionInterface(;
            name = String(row.flowgate_id),
            available = true,
            active_power_flow_limits = (min = -row.fmax, max = row.fmax),
            direction_mapping = dirs,
        )
        add_service!(sys, iface, branches)
        stats["flowgates"] += 1
    end
end

# ------------------------------------------------- reconexión de islas -------

# La capa canónica marca fuera de servicio (caso base) algunos enlaces que en la
# operación real están energizados: quedan islas con demanda asignada (VEROPE)
# y sin generación, que MODOM sí sirve (su ENS ahí es 0). Reconexión mínima:
# para cada isla deficitaria se reactiva/crea el enlace físico del catálogo de
# ramas hacia la red principal, uno por isla y pasada, hasta eliminar el déficit.
function _reconnect_deficient_islands!(sys::System, t, stats)
    stats["ramas_reconectadas"] = 0
    demanda = Dict{String,Float64}()
    for g in groupby(t["loads"], :load_id)
        demanda[String(first(g.load_id))] = maximum(_num.(g.p_set_mw, 0.0))
    end
    capacidad = Dict{String,Float64}()
    for row in eachrow(t["generators"])
        b = String(row.bus_id)
        capacidad[b] = get(capacidad, b, 0.0) + _num(row.effective_pmax_mw, 0.0)
    end

    for _ in 1:20
        # islas sobre ramas disponibles
        uf_parent = Dict{String,String}()
        _f(x) = (get!(uf_parent, x, x);
                 while uf_parent[x] != x
                     uf_parent[x] = uf_parent[uf_parent[x]]; x = uf_parent[x]
                 end; x)
        for b in get_components(ACBus, sys)
            _f(get_name(b))
        end
        for T in (Line, Transformer2W), br in get_components(T, sys)
            get_available(br) || continue
            a = get_arc(br)
            ra, rb = _f(get_name(get_from(a))), _f(get_name(get_to(a)))
            ra != rb && (uf_parent[ra] = rb)
        end
        islas = Dict{String,Vector{String}}()
        for b in get_components(ACBus, sys)
            push!(get!(islas, _f(get_name(b)), String[]), get_name(b))
        end
        dem(v) = sum(get(demanda, x, 0.0) for x in v; init = 0.0)
        cap(v) = sum(get(capacidad, x, 0.0) for x in v; init = 0.0)
        main_root = argmax(k -> dem(islas[k]), collect(keys(islas)))
        main_set = Set(islas[main_root])

        reconectado = false
        for (root, v) in islas
            root == main_root && continue
            dem(v) - cap(v) > 0.5 || continue
            vset = Set(v)
            # preferir enlace directo a la isla principal; si no hay, a cualquier
            # otra isla (las pasadas sucesivas lo fusionan todo con la principal)
            candidatos = NamedTuple[]
            for row in eachrow(t["branches"])
                fb, tb = String(row.from_bus), String(row.to_bus)
                interno = (fb in vset) == (tb in vset)
                interno && continue
                a_main = (fb in main_set) || (tb in main_set)
                push!(candidatos, (row = row, a_main = a_main))
            end
            isempty(candidatos) && continue
            sort!(candidatos; by = c -> !c.a_main)
            for c in candidatos[1:1]
                row = c.row
                name = String(row.branch_id)
                br = get_component(Line, sys, name)
                br === nothing && (br = get_component(Transformer2W, sys, name))
                if br !== nothing
                    set_available!(br, true)
                else
                    fbus = get_component(ACBus, sys, String(row.from_bus))
                    tbus = get_component(ACBus, sys, String(row.to_bus))
                    (fbus === nothing || tbus === nothing) && continue
                    arc = Arc(fbus, tbus)
                    add_component!(sys, arc)
                    add_component!(sys, Transformer2W(; name = name * " (reconectada)",
                        available = true, active_power_flow = 0.0,
                        reactive_power_flow = 0.0, arc,
                        r = max(_num(row.r_pu, 0.0), 0.0),
                        x = max(abs(_num(row.x_pu, 1e-4)), 1e-5),
                        primary_shunt = 0.0, rating = 99.99))
                end
                stats["ramas_reconectadas"] += 1
                reconectado = true
                break
            end
        end
        reconectado || break
    end
end

# ------------------------------------------------------------- referencia ----

"Barra de referencia: la del generador térmico de mayor capacidad."
function _set_reference_bus!(sys::System, t)
    gens = collect(get_components(ThermalStandard, sys))
    isempty(gens) && return
    slack = argmax(g -> get_base_power(g) * get_active_power_limits(g).max, gens)
    set_bustype!(get_bus(slack), ACBusTypes.REF)
end

# ---------------------------------------------------------------- reporte ----

function _report(sys::System, t, stats)
    set_units_base_system!(sys, "NATURAL_UNITS")
    println("── System SENI (despacho MODOM) ──")
    println("  Barras:      ", length(get_components(ACBus, sys)), " (canónico: ", nrow(t["buses"]), ")")
    println("  Líneas:      ", stats["lineas"], "  Trafos: ", stats["trafos"],
            "  (omitidas: ", stats["ramas_omitidas"], ")")
    println("  Térmicos:    ", stats["termicos"], "  Hidro: ", stats["hidro"],
            "  Renovables: ", stats["renovables"], "  (omitidos: ", stats["gens_omitidos"], ")")
    println("  Cargas:      ", stats["cargas"], "  (omitidas: ", stats["cargas_omitidas"], ")")
    println("  Flowgates:   ", stats["flowgates"],
            "  Ramas por flujo MODOM: ", stats["ramas_por_flujo"],
            "  Reconectadas (islas): ", stats["ramas_reconectadas"])
    # con NATURAL_UNITS los getters devuelven MW directamente
    cap(T) = sum(get_active_power_limits(g).max for g in get_components(T, sys); init = 0.0)
    println("  Capacidad térmica:   ", round(cap(ThermalStandard); digits = 1), " MW")
    println("  Capacidad hidro:     ", round(cap(HydroDispatch); digits = 1), " MW")
    println("  Capacidad renovable: ",
            round(sum(get_base_power(g) for g in get_components(RenewableDispatch, sys); init = 0.0); digits = 1),
            " MW")
    set_units_base_system!(sys, "DEVICE_BASE")
end
