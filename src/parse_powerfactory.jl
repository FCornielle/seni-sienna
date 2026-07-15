# Fase 2 — System FÍSICO del SENI desde el export de PowerFactory
# (data/raw/salida_PDD_*). Replica la receta probada de modom-pypsa
# (ac_digsilent.py, pandapower) en PowerSystems.jl:
#
#  1. Fusión de terminales node-breaker por interruptores CERRADOS y por
#     "jumpers" (líneas con R<0.05 Ω y X<0.05 Ω) → union-find. Evita lazos de
#     impedancia ~0 que singularizan el Jacobiano.
#  2. Un ACBus por nodo eléctrico (raíz del union-find).
#  3. Líneas/trafos por PATH de terminal (barra_*_id); trafos con uk%/ukr% del
#     tipo, en pu del sistema (100 MVA).
#  4. Síncronos AGREGADOS por nodo (P_desp × num_unidades, consigna del mayor);
#     slack = ref_slack=1 → barra REF. Estáticos como inyección PQ fija.
#  5. Solo se instancia la isla eléctrica principal (la que contiene el slack).
#
# Desviación deliberada de modom-pypsa: aquí SÍ se filtra outserv=1 en ramas e
# interruptores, porque el objetivo es reproducir el flujo de PowerFactory
# (referencia_loadflow.csv del escenario P20), que excluye lo fuera de servicio.

"Union-find sobre strings."
mutable struct _UF
    parent::Dict{String,String}
end
_UF() = _UF(Dict{String,String}())

function _find(uf::_UF, x::String)
    get!(uf.parent, x, x)
    while uf.parent[x] != x
        uf.parent[x] = uf.parent[uf.parent[x]]
        x = uf.parent[x]
    end
    return x
end

_union!(uf::_UF, a::String, b::String) = (ra = _find(uf, a); rb = _find(uf, b);
                                          ra != rb && (uf.parent[ra] = rb); nothing)

_s(x) = x === missing ? "" : String(strip(string(x)))
_closed(x) = _s(x) in ("1", "1.0", "True", "true")
_inservice(row) = _num(row.outserv, 0.0) != 1.0

"""
    build_seni_physical_system(raw_dir; export_name) -> (System, Dict for_name→bus_name)

Construye el System físico AC del SENI desde el export PowerFactory y devuelve
también el mapa for_name (código MODOM del terminal) → nombre del ACBus, para
cruzar resultados con la referencia de PowerFactory y con las 717 barras MODOM.
"""
function build_seni_physical_system(
    raw_dir::AbstractString;
    export_name::AbstractString = "salida_PDD_30_09_2025",
)
    d = joinpath(raw_dir, export_name)
    barras = _read_csv(d, "barras.csv")
    lineas = _read_csv(d, "lineas.csv")
    trafos = _read_csv(d, "transformadores2.csv")
    tipos_t2 = _read_csv(d, "tipos_transformadores2.csv")
    cargas = _read_csv(d, "cargas.csv")
    gsinc = _read_csv(d, "generadores_sinc.csv")
    tipos_g = _read_csv(d, "tipos_generadores.csv")
    gest = _read_csv(d, "generadores_est.csv")
    shunts = _read_csv(d, "shunts.csv")
    inter = _read_csv(d, "interruptores.csv")

    # ---- 1. fusión de terminales -------------------------------------------
    uf = _UF()
    for row in eachrow(barras)
        _find(uf, _s(row.ruta))
    end
    for row in eachrow(inter)
        (_inservice(row) && _closed(row.cerrado)) || continue
        bi, bj = _s(row.barra_i_id), _s(row.barra_j_id)
        (haskey(uf.parent, bi) && haskey(uf.parent, bj)) && _union!(uf, bi, bj)
    end
    for row in eachrow(lineas)
        _inservice(row) || continue
        if abs(_num(row.R1_ohm, 9.9)) < 0.05 && abs(_num(row.X1_ohm, 9.9)) < 0.05
            bi, bj = _s(row.barra_i_id), _s(row.barra_j_id)
            (haskey(uf.parent, bi) && haskey(uf.parent, bj)) && _union!(uf, bi, bj)
        end
    end

    # ---- 2. nodos eléctricos -----------------------------------------------
    node_of = Dict{String,String}()        # ruta terminal → id de nodo (raíz)
    node_vn = Dict{String,Float64}()
    node_name = Dict{String,String}()
    forname_to_node = Dict{String,String}()
    used_names = Dict{String,Int}()
    for row in eachrow(barras)
        ruta = _s(row.ruta)
        root = _find(uf, ruta)
        node_of[ruta] = root
        if !haskey(node_vn, root)
            vn = _num(row.U_nom_kV, 0.0)
            node_vn[root] = vn > 0 ? vn : 1.0
            base = _s(row.loc_name) * " " * string(round(node_vn[root]; digits = 1)) * "kV"
            n = get(used_names, base, 0); used_names[base] = n + 1
            node_name[root] = n == 0 ? base : base * " #" * string(n + 1)
        end
        fn = uppercase(_s(row.for_name))
        (startswith(fn, "W") && !haskey(forname_to_node, fn)) && (forname_to_node[fn] = root)
    end

    # ---- 3. ramas candidatas (para la isla principal) -----------------------
    # (tipo, from_node, to_node, r_pu, x_pu, b_pu, rating_pu, nombre)
    edges = NamedTuple[]
    tipo_por_nombre = Dict(_s(t.loc_name) => t for t in eachrow(tipos_t2))
    tipo_por_ruta = Dict(_s(t.ruta) => t for t in eachrow(tipos_t2))

    for row in eachrow(lineas)
        _inservice(row) || continue
        ni = get(node_of, _s(row.barra_i_id), "")
        nj = get(node_of, _s(row.barra_j_id), "")
        (isempty(ni) || isempty(nj) || ni == nj) && continue
        R, X = _num(row.R1_ohm, 0.0), _num(row.X1_ohm, 0.0)
        (R == 0 && X == 0) && continue
        kv = node_vn[ni]
        zb = kv^2 / MODOM_SBASE
        par = max(_num(row.num_paralelas, 1.0), 1.0)
        b_total = max(_num(row.B1_uS, 0.0), 0.0) * 1e-6 * zb * par
        rating = sqrt(3) * kv * max(_num(row.I_nom_kA, 1.0), 0.01) * par / MODOM_SBASE
        push!(edges, (tipo = :line, ni = ni, nj = nj,
                      r = max(R, 0.0) / zb / par,
                      x = max(abs(X), 1e-4) / zb / par,
                      b = b_total, rating = rating, tap = 1.0,
                      name = _s(row.loc_name)))
    end

    n_traf_sin_tipo = 0
    for row in eachrow(trafos)
        _inservice(row) || continue
        ni = get(node_of, _s(row.barra_AT_id), "")
        nj = get(node_of, _s(row.barra_BT_id), "")
        (isempty(ni) || isempty(nj) || ni == nj) && continue
        tid = _s(row.typ_id)
        typ = get(tipo_por_nombre, tid,
              get(tipo_por_ruta, tid,
              get(tipo_por_nombre, replace(split(tid, "\\")[end], ".TypTr2" => ""), nothing)))
        if typ === nothing
            n_traf_sin_tipo += 1
            continue
        end
        sn = _num(typ.S_nom_MVA, 0.0)
        uk = clamp(_num(typ.uk_pct, 0.0), 0.5, 40.0)
        sn <= 0 && (n_traf_sin_tipo += 1; continue)
        ukr = _num(typ.ukr_pct, 0.0)
        ukr <= 0 && (ukr = _num(typ.Pcu_kW, 0.0) / (10 * sn))  # Pcu → ukr%
        ukr = clamp(ukr, 0.0, uk * 0.99)
        par = max(_num(row.num_paralelos, 1.0), 1.0)
        # tap fijo del escenario: Δ = (posición − neutro) · dU%/100, aplicado
        # en el lado AT (tap_lado=0) o BT (=1) → relación equivalente lado AT
        dtap = (_num(row.tap_actual, 0.0) - _num(typ.tap_neutro, 0.0)) *
               _num(typ.tap_dU_pct, 0.0) / 100
        tap = _num(typ.tap_lado, 0.0) == 1.0 ? 1 / (1 + dtap) : 1 + dtap
        push!(edges, (tipo = :trafo, ni = ni, nj = nj,
                      r = ukr / 100 * MODOM_SBASE / sn / par,
                      x = uk / 100 * MODOM_SBASE / sn / par,
                      b = 0.0, rating = sn * par / MODOM_SBASE,
                      tap = clamp(tap, 0.8, 1.2), name = _s(row.loc_name)))
    end

    # ---- 4. isla principal (la del slack) -----------------------------------
    conn = _UF()
    for e in edges
        _union!(conn, e.ni, e.nj)
    end
    slack_node = ""
    for row in eachrow(gsinc)
        (_inservice(row) && _closed(row.ref_slack)) || continue
        slack_node = get(node_of, _s(row.barra_con_id), "")
        isempty(slack_node) || break
    end
    main_root = if !isempty(slack_node)
        _find(conn, slack_node)
    else
        # respaldo: componente con más nodos
        cnt = Dict{String,Int}()
        for root in values(node_of)
            cnt[_find(conn, root)] = get(cnt, _find(conn, root), 0) + 1
        end
        argmax(r -> cnt[r], collect(keys(cnt)))
    end
    in_main(node) = !isempty(node) && _find(conn, node) == main_root

    # ---- 5. System -----------------------------------------------------------
    sys = System(MODOM_SBASE)
    bus_of_node = Dict{String,ACBus}()
    num = 0
    for (root, vn) in node_vn
        in_main(root) || continue
        num += 1
        bus = ACBus(; number = num, name = node_name[root], bustype = ACBusTypes.PQ,
                    angle = 0.0, magnitude = 1.0,
                    voltage_limits = (min = 0.9, max = 1.1), base_voltage = vn)
        add_component!(sys, bus)
        bus_of_node[root] = bus
    end

    arcs = Dict{Tuple{String,String},Arc}()
    stats = Dict("lineas" => 0, "trafos" => 0)
    used_branch = Dict{String,Int}()
    for e in edges
        (in_main(e.ni) && in_main(e.nj)) || continue
        arc = get!(arcs, (e.ni, e.nj)) do
            a = Arc(bus_of_node[e.ni], bus_of_node[e.nj]); add_component!(sys, a); a
        end
        n = get(used_branch, e.name, 0); used_branch[e.name] = n + 1
        bname = n == 0 ? e.name : e.name * " #" * string(n + 1)
        if e.tipo == :line && get_base_voltage(bus_of_node[e.ni]) == get_base_voltage(bus_of_node[e.nj])
            add_component!(sys, Line(; name = bname, available = true,
                active_power_flow = 0.0, reactive_power_flow = 0.0, arc,
                r = e.r, x = e.x, b = (from = e.b / 2, to = e.b / 2),
                rating = e.rating, angle_limits = (min = -π / 2, max = π / 2)))
            stats["lineas"] += 1
        elseif e.tap != 1.0
            add_component!(sys, TapTransformer(; name = bname, available = true,
                active_power_flow = 0.0, reactive_power_flow = 0.0, arc,
                r = e.r, x = e.x, primary_shunt = 0.0, tap = e.tap,
                rating = e.rating))
            stats["trafos"] += 1
        else
            add_component!(sys, Transformer2W(; name = bname, available = true,
                active_power_flow = 0.0, reactive_power_flow = 0.0, arc,
                r = e.r, x = e.x, primary_shunt = 0.0, rating = e.rating))
            stats["trafos"] += 1
        end
    end

    # cargas
    stats["cargas"] = 0
    for row in eachrow(cargas)
        _inservice(row) || continue
        node = get(node_of, _s(row.barra_con_id), "")
        in_main(node) || continue
        stats["cargas"] += 1
        add_component!(sys, PowerLoad(;
            name = "load_" * string(stats["cargas"]) * "_" * _s(row.loc_name),
            available = true, bus = bus_of_node[node],
            active_power = _num(row.P_MW, 0.0) / MODOM_SBASE,
            reactive_power = _num(row.Q_Mvar, 0.0) / MODOM_SBASE,
            base_power = MODOM_SBASE,
            max_active_power = _num(row.P_MW, 0.0) / MODOM_SBASE,
            max_reactive_power = _num(row.Q_Mvar, 0.0) / MODOM_SBASE))
    end

    # shunts (capacitor inyecta B>0; reactor B<0)
    stats["shunts"] = 0
    for row in eachrow(shunts)
        _inservice(row) || continue
        node = get(node_of, _s(row.barra_con_id), "")
        q = _num(row.Q_nom_Mvar, 0.0)
        (in_main(node) && abs(q) > 1e-9) || continue
        stats["shunts"] += 1
        # tipo_shunt 2 = capacitor (inyecta), 4 = reactor (absorbe)
        sgn = _s(row.tipo_shunt) == "4" ? -1.0 : 1.0
        add_component!(sys, FixedAdmittance(;
            name = "shunt_" * string(stats["shunts"]) * "_" * _s(row.loc_name),
            available = true, bus = bus_of_node[node],
            Y = complex(0.0, sgn * abs(q) / MODOM_SBASE)))
    end

    # síncronos agregados por nodo, con límites de Q reales del tipo de máquina
    gtyp_by_name = Dict(_s(t.loc_name) => t for t in eachrow(tipos_g))
    agg = Dict{String,Dict{Symbol,Float64}}()
    for row in eachrow(gsinc)
        _inservice(row) || continue
        node = get(node_of, _s(row.barra_con_id), "")
        in_main(node) || continue
        nu = max(_num(row.num_unidades, 1.0), 1.0)
        p = _num(row.P_desp_MW, 0.0) * nu
        vm = _num(row.U_consigna_pu, 1.0)
        (0.9 <= vm <= 1.1) || (vm = 1.0)
        typ = get(gtyp_by_name, _s(row.typ_id),
              get(gtyp_by_name, replace(split(_s(row.typ_id), "\\")[end], ".TypSym" => ""), nothing))
        qmax = typ !== nothing ? _num(typ.Q_max_Mvar, 0.0) * nu :
               0.6 * _num(row.P_max_MW, 0.0) * nu
        qmin = typ !== nothing ? _num(typ.Q_min_Mvar, 0.0) * nu :
               -0.4 * _num(row.P_max_MW, 0.0) * nu
        a = get!(agg, node, Dict(:p => 0.0, :vm => vm, :pmax => -1.0,
                                 :qmin => 0.0, :qmax => 0.0))
        a[:p] += p
        a[:qmin] += min(qmin, 0.0)
        a[:qmax] += max(qmax, 0.0)
        p > a[:pmax] && (a[:pmax] = p; a[:vm] = vm)
    end
    slack_in_main = in_main(slack_node)
    stats["gens"] = 0
    for (node, a) in agg
        bus = bus_of_node[node]
        is_slack = slack_in_main && node == slack_node
        set_bustype!(bus, is_slack ? ACBusTypes.REF : ACBusTypes.PV)
        set_magnitude!(bus, a[:vm])
        stats["gens"] += 1
        add_component!(sys, ThermalStandard(;
            name = "gen_" * string(stats["gens"]) * "_" * get_name(bus),
            available = true, status = true, bus,
            active_power = a[:p] / MODOM_SBASE, reactive_power = 0.0, rating = 99.9,
            active_power_limits = (min = 0.0, max = 99.9),
            reactive_power_limits = (min = min(a[:qmin], -0.01) / MODOM_SBASE,
                                     max = max(a[:qmax], 0.01) / MODOM_SBASE),
            ramp_limits = nothing,
            operation_cost = ThermalGenerationCost(;
                variable = CostCurve(LinearCurve(0.0)),
                fixed = 0.0, start_up = 0.0, shut_down = 0.0),
            base_power = MODOM_SBASE, time_limits = nothing,
            prime_mover_type = PrimeMovers.OT, fuel = ThermalFuels.OTHER))
    end
    if !slack_in_main
        # respaldo: REF en la barra PV de mayor tensión
        pvs = [b for b in values(bus_of_node) if get_bustype(b) == ACBusTypes.PV]
        isempty(pvs) && error("Sin barras PV para asignar slack")
        set_bustype!(argmax(get_base_voltage, pvs), ACBusTypes.REF)
    end

    # estáticos como inyección PQ fija
    stats["estaticos"] = 0
    for row in eachrow(gest)
        _inservice(row) || continue
        node = get(node_of, _s(row.barra_con_id), "")
        in_main(node) || continue
        nu = max(_num(row.num_unidades, 1.0), 1.0)
        stats["estaticos"] += 1
        add_component!(sys, RenewableDispatch(;
            name = "vre_" * string(stats["estaticos"]) * "_" * _s(row.loc_name),
            available = true, bus = bus_of_node[node],
            active_power = _num(row.P_desp_MW, 0.0) * nu / MODOM_SBASE,
            reactive_power = _num(row.Q_desp_Mvar, 0.0) * nu / MODOM_SBASE,
            rating = 99.9, prime_mover_type = PrimeMovers.PVe,
            reactive_power_limits = (min = -99.9, max = 99.9), power_factor = 1.0,
            operation_cost = RenewableGenerationCost(CostCurve(LinearCurve(0.0))),
            base_power = MODOM_SBASE))
    end

    forname_to_bus = Dict(fn => get_name(bus_of_node[node])
                          for (fn, node) in forname_to_node if in_main(node))

    println("── System SENI físico (export PF, isla principal) ──")
    println("  Nodos eléctricos: ", length(bus_of_node), " (terminales: ", nrow(barras), ")")
    println("  Líneas: ", stats["lineas"], "  Trafos: ", stats["trafos"],
            "  (trafos sin tipo: ", n_traf_sin_tipo, ")")
    println("  Cargas: ", stats["cargas"], "  Shunts: ", stats["shunts"],
            "  Gen sinc (nodos): ", stats["gens"], "  Estáticos: ", stats["estaticos"])
    println("  Slack: ", slack_in_main ? node_name[slack_node] : "respaldo (mayor kV)")
    return sys, forname_to_bus
end
