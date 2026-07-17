# Fase 5 — Capa dinámica: DynamicGenerator de PSID para cada nodo de generación
# síncrona del System físico.
#
# Nivel v1 (documentado en validation/fase5_dinamica.md):
#  - Máquina: parámetros eléctricos REALES del export (sym_extra.csv → TypSym):
#    GENROU (RoundRotorQuadratic) si iturbo=1, GENSAL (SalientPoleQuadratic) si 0,
#    en la base MVA de la máquina dominante del nodo × unidades.
#  - AVR: SEXS con parámetros típicos (mapeo fino DSL→PSID es v2)
#  - Governor: TGOV1 típico (térmico/diésel) o HYGOV típico (hidro)
#  - PSS: fijo (sin señal) en v1
#  - Datos incompletos → máquina clásica (BaseMachine + AVRFixed)

const _TYP_SEXS = (Ta_Tb = 0.1, Tb = 10.0, K = 100.0, Te = 0.1,
                   V_lim = (min = -4.0, max = 5.0))

# límites con cabeceo (1.2) y VELM laxo: evita discontinuidades duras del
# integrador DAE en el evento (v1; los límites reales llegan con el mapeo DSL)
# topes 2.0: el slack inicializa por encima de su despacho (absorbe pérdidas)
# y los límites duros estancan el DAE en el evento (v1; límites reales en v2)
_gov_tgov1() = SteamTurbineGov1(;
    R = 0.05, T1 = 0.5, valve_position_limits = (min = 0.0, max = 2.0),
    T2 = 2.1, T3 = 7.0, D_T = 0.0, DB_h = 0.0, DB_l = 0.0, T_rate = 0.0)

_gov_hygov() = HydroTurbineGov(;
    R = 0.05, r = 0.3, Tr = 5.0, Tf = 0.05, Tg = 0.5, VELM = 0.5,
    gate_position_limits = (min = 0.0, max = 2.0), Tw = 1.0, At = 1.2,
    D_T = 0.2, q_nl = 0.08)

"Lee sym_extra.csv (parámetros de máquina + vínculo por sym_for_name/loc_name)."
function load_machine_params(dyn_dir::AbstractString)
    df = CSV.read(joinpath(dyn_dir, "sym_extra.csv"), DataFrame)
    by_for = Dict{String,Any}()
    by_loc = Dict{String,Any}()
    for row in eachrow(df)
        fn = _s(row.sym_for_name)
        !isempty(fn) && (by_for[fn] = row)
        by_loc[_s(row.sym_loc_name)] = row
    end
    return by_for, by_loc
end

function _machine_from_row(row)
    xd, xq = _num(row.xd, 0.0), _num(row.xq, 0.0)
    xds, xdss = _num(row.xds, 0.0), _num(row.xdss, 0.0)
    xqs, xqss = _num(row.xqs, 0.0), _num(row.xqss, 0.0)
    xl = _num(row.xl, 0.0)
    r = max(_num(row.rstr, 0.0), 0.0)
    td0 = _num(row.tds0, 0.0)
    td0s = max(_num(row.tdss0, 0.0), 0.01)
    tq0s = max(_num(row.tqss0, 0.0), 0.01)
    tq0 = _num(row.tqs0, 0.0)
    completo = td0 > 0 && xd > xds > xdss > 0 && xq > 0
    completo || return nothing
    xl = clamp(xl, 0.0, 0.95 * xdss)
    if _num(row.iturbo, 0.0) == 1.0  # rotor liso → GENROU
        tq0 <= 0 && (tq0 = 0.8)
        xqs <= xdss && (xqs = max(xqs, 1.05 * xdss))
        return RoundRotorQuadratic(;
            R = r, Td0_p = td0, Td0_pp = td0s, Tq0_p = tq0, Tq0_pp = tq0s,
            Xd = xd, Xq = xq, Xd_p = xds, Xq_p = min(xqs, xq * 0.99),
            Xd_pp = xdss, Xl = xl, Se = (0.0, 0.0))
    else                              # polos salientes → GENSAL
        return SalientPoleQuadratic(;
            R = r, Td0_p = td0, Td0_pp = td0s, Tq0_pp = tq0s,
            Xd = xd, Xq = xq, Xd_p = xds, Xd_pp = xdss, Xl = xl,
            Se = (0.0, 0.0))
    end
end

_es_hidro(categoria::AbstractString) = occursin(r"hidro|hydro"i, categoria)

"""
    attach_dynamic_models!(sys, raw_dir; dyn_export) -> (n_detallados, n_clasicos)

Adjunta un DynamicGenerator a cada ThermalStandard del System físico usando la
máquina dominante del nodo (ext["maquinas"]). Ajusta base_power del estático a
los MVA reales del nodo para que los pu de máquina sean coherentes.
"""
function attach_dynamic_models!(
    sys::System, raw_dir::AbstractString;
    dyn_export::AbstractString = joinpath("salida_dinamica_20260714",
                                          "salida_dinamica_20260714_203429"),
    avr_mode::Symbol = :sexs,   # :sexs | :sexs_wide | :fixed (diagnóstico numérico)
    gov_mode::Symbol = :tipico, # :tipico | :sin_hygov (hidro→TGOV1) | :fixed
)
    by_for, by_loc = load_machine_params(joinpath(raw_dir, dyn_export))
    set_units_base_system!(sys, "NATURAL_UNITS")
    n_full = 0; n_clasico = 0
    for gen in collect(get_components(ThermalStandard, sys))
        ext = get_ext(gen)
        maqs = get(ext, "maquinas", NamedTuple[])
        dom = isempty(maqs) ? nothing : argmax(m -> m.p_mw, maqs)
        row = dom === nothing ? nothing :
              get(by_for, dom.for_name, get(by_loc, dom.loc_name, nothing))

        # base MVA real del nodo (los parámetros de máquina están en su propia base)
        p_mw = get_active_power(gen)
        qlim = get_reactive_power_limits(gen)
        smva = max(get(ext, "smva", 0.0), p_mw * 1.3, 1.0)
        set_base_power!(gen, smva)
        set_active_power!(gen, p_mw)
        set_reactive_power!(gen, 0.0)
        set_active_power_limits!(gen, (min = 0.0, max = 1.0))
        set_reactive_power_limits!(gen, (min = -0.6, max = 0.6))
        set_rating!(gen, smva)

        maquina = row === nothing ? nothing : _machine_from_row(row)
        h = row === nothing ? 3.0 : max(_num(row.h, 0.0), 0.5)
        categoria = dom === nothing ? "" : dom.categoria
        gov = if gov_mode == :fixed
            TGFixed(; efficiency = 1.0)
        elseif gov_mode == :sin_hygov
            _gov_tgov1()
        else
            _es_hidro(categoria) ? _gov_hygov() : _gov_tgov1()
        end

        avr = if avr_mode == :fixed
            AVRFixed(; Vf = 1.0)
        else
            vlim = avr_mode == :sexs_wide ? (min = -99.0, max = 99.0) : _TYP_SEXS.V_lim
            SEXS(; Ta_Tb = _TYP_SEXS.Ta_Tb, Tb = _TYP_SEXS.Tb,
                 K = _TYP_SEXS.K, Te = _TYP_SEXS.Te, V_lim = vlim)
        end
        if maquina === nothing
            dyn = DynamicGenerator(;
                name = get_name(gen), ω_ref = 1.0,
                machine = BaseMachine(; R = 0.0, Xd_p = 0.3, eq_p = 1.0),
                shaft = SingleMass(; H = h, D = 2.0),
                avr = AVRFixed(; Vf = 1.0),
                prime_mover = gov, pss = PSSFixed(; V_pss = 0.0))
            n_clasico += 1
        else
            dyn = DynamicGenerator(;
                name = get_name(gen), ω_ref = 1.0,
                machine = maquina,
                shaft = SingleMass(; H = h, D = 0.0),
                avr = avr,
                prime_mover = gov, pss = PSSFixed(; V_pss = 0.0))
            n_full += 1
        end
        add_component!(sys, dyn, gen)
    end
    # inversores estáticos sin modelo dinámico → fuera de servicio en dinámica
    # (13 unidades, ~13 MW en el escenario nocturno; v2: DynamicInverter WECC)
    for g in get_components(RenewableDispatch, sys)
        set_available!(g, false)
    end
    _loads_to_impedance!(sys)
    @info "Capa dinámica adjunta" detallados = n_full clasicos = n_clasico
    return n_full, n_clasico
end

# Cargas como impedancia constante para RMS: con potencia constante, los
# bolsones a V≈0.8 pu del escenario colapsan la red algebraica tras el evento
# (PF también usa cargas dependientes de tensión: TypLod aP/bP/cP/kpu).
function _loads_to_impedance!(sys::System)
    for load in collect(get_components(PowerLoad, sys))
        p = get_active_power(load)    # MW (unidades naturales)
        q = get_reactive_power(load)
        bus = get_bus(load)
        name = get_name(load)
        remove_component!(sys, load)
        add_component!(sys, StandardLoad(;
            name, available = true, bus,
            base_power = MODOM_SBASE,
            constant_active_power = 0.0, constant_reactive_power = 0.0,
            impedance_active_power = p / MODOM_SBASE,
            impedance_reactive_power = q / MODOM_SBASE,
            current_active_power = 0.0, current_reactive_power = 0.0,
            max_constant_active_power = 0.0, max_constant_reactive_power = 0.0,
            max_impedance_active_power = p / MODOM_SBASE,
            max_impedance_reactive_power = q / MODOM_SBASE,
            max_current_active_power = 0.0, max_current_reactive_power = 0.0))
    end
end