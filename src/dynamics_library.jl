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

# topes 2.0: el slack inicializa por encima de su despacho (absorbe pérdidas)
# y los límites duros estancan el DAE en el evento
_gov_tgov1(R = 0.05) = SteamTurbineGov1(;
    R = R, T1 = 0.5, valve_position_limits = (min = 0.0, max = 2.0),
    T2 = 2.1, T3 = 7.0, D_T = 0.0, DB_h = 0.0, DB_l = 0.0, T_rate = 0.0)

_gov_hygov(R = 0.05) = HydroTurbineGov(;
    R = R, r = 0.3, Tr = 5.0, Tf = 0.05, Tg = 0.5, VELM = 0.5,
    gate_position_limits = (min = 0.0, max = 2.0), Tw = 1.0, At = 1.2,
    D_T = 0.2, q_nl = 0.08)

# ------------------ v2: parámetros DSL reales (dsl_parametros.csv) ------------

"dsl_parametros.csv → Dict maquina_for_name → model_name → (param → valor)."
function load_dsl_params(dyn_dir::AbstractString)
    df = CSV.read(joinpath(dyn_dir, "dsl_parametros.csv"), DataFrame)
    out = Dict{String,Dict{String,Dict{String,Float64}}}()
    for row in eachrow(df)
        maq = _s(row.maquina_for_name)
        isempty(maq) && continue
        v = tryparse(Float64, _s(row.param_value))
        v === nothing && continue
        get!(get!(get!(out, maq, Dict{String,Dict{String,Float64}}()),
                  _s(row.model_name), Dict{String,Float64}()),
             _s(row.param_name), v)
    end
    return out
end

_p(d, k, def) = get(d, k, def)

"Governor con parámetros DSL reales; degrada conservando el droop real."
function _gov_from_dsl(modelos::Dict{String,Dict{String,Float64}}, categoria)
    for (nombre, d) in modelos
        if startswith(nombre, "gov_GGOV1")
            # PSID 0.15 no implementa initialize_tg! para GeneralGovModel →
            # TGOV1 con los parámetros REALES dominantes del GGOV1 (droop r,
            # actuador Tact y turbina Tb)
            r = clamp(_p(d, "r", 0.05), 0.02, 0.12)
            gg = SteamTurbineGov1(; R = r,
                T1 = max(_p(d, "Tact", 0.5), 0.05),
                valve_position_limits = (min = 0.0, max = 2.0),
                T2 = max(_p(d, "Tb", 0.5), 0.1), T3 = 7.0,
                D_T = 0.0, DB_h = 0.0, DB_l = 0.0, T_rate = 0.0)
            return (gg, :ggov1_tgov1)
        elseif startswith(nombre, "gov_HYGOV")
            R = clamp(_p(d, "R", 0.05), 0.02, 0.12)
            hg = try
                HydroTurbineGov(; R = R, r = max(_p(d, "r", 0.3), 0.05),
                    Tr = max(_p(d, "Tr", 5.0), 0.5),
                    Tf = max(_p(d, "Tf", 0.05), 0.01), Tg = max(_p(d, "Tg", 0.5), 0.1),
                    VELM = 0.5, gate_position_limits = (min = 0.0, max = 2.0),
                    Tw = max(_p(d, "Tw", 1.0), 0.3), At = max(_p(d, "At", 1.2), 0.8),
                    D_T = _p(d, "Dturb", 0.2), q_nl = max(_p(d, "qnl", 0.08), 0.0))
            catch
                nothing
            end
            return hg === nothing ? (_gov_hygov(R), :hygov_fb) : (hg, :hygov)
        elseif startswith(nombre, "gov_DEGOV1")
            r = clamp(_p(d, "Droop", 0.05), 0.02, 0.12)
            dg = try
                DEGOV1(; flag = Int(round(_p(d, "Droop_Control", 1))),
                    Td = max(_p(d, "TD", 0.01), 0.005),
                    T1 = max(_p(d, "T1", 0.2), 0.01), T2 = _p(d, "T2", 0.3),
                    T3 = max(_p(d, "T3", 0.5), 0.01), K = _p(d, "K", 10.0),
                    T4 = max(_p(d, "T4", 1.0), 0.01), T5 = _p(d, "T5", 0.1),
                    T6 = max(_p(d, "T6", 0.2), 0.01), Te = max(_p(d, "TE", 0.1), 0.01),
                    R = r)
            catch
                nothing
            end
            return dg === nothing ? (_gov_tgov1(r), :degov1_fb) : (dg, :degov1)
        end
    end
    return (_es_hidro(categoria) ? _gov_hygov() : _gov_tgov1(), :tipico)
end

"AVR con parámetros DSL reales; degrada a SEXS típico."
function _avr_from_dsl(modelos::Dict{String,Dict{String,Float64}})
    for (nombre, d) in modelos
        if startswith(nombre, "vco_EXAC1")
            a = try
                EXAC1(; Tr = max(_p(d, "Tr", 0.02), 0.005), Tb = _p(d, "Tb", 0.0),
                    Tc = _p(d, "Tc", 0.0), Ka = clamp(_p(d, "Ka", 200.0), 10.0, 500.0),
                    Ta = max(_p(d, "Ta", 0.02), 0.005),
                    # Vrmax/Vrmin reales no vinieron en el export DSL; el init
                    # de PF requiere V_R hasta ~16.5 → límites amplios (v2)
                    Vr_lim = (min = -20.0, max = 20.0),
                    Te = max(_p(d, "Te", 0.8), 0.05), Kf = _p(d, "Kf", 0.03),
                    Tf = max(_p(d, "Tf", 1.0), 0.1), Kc = _p(d, "Kc", 0.2),
                    Kd = _p(d, "Kd", 0.4), Ke = _p(d, "Ke", 1.0),
                    E_sat = (_p(d, "E1", 4.0), _p(d, "E2", 5.3)),
                    Se = (_p(d, "Se1", 0.1), _p(d, "Se2", 0.5)))
            catch
                nothing
            end
            a !== nothing && return (a, :exac1)
        elseif startswith(nombre, "vco_IEEET1") || startswith(nombre, "avr_ESAC5A")
            a = try
                AVRTypeI(; Ka = clamp(_p(d, "Ka", 100.0), 10.0, 500.0),
                    Ke = _p(d, "Ke", 1.0), Kf = max(_p(d, "Kf", 0.03), 0.001),
                    Ta = max(_p(d, "Ta", 0.02), 0.005), Te = max(_p(d, "Te", 0.8), 0.05),
                    Tf = max(_p(d, "Tf", _p(d, "Tf1", 1.0)), 0.1),
                    Tr = max(_p(d, "Tr", 0.02), 0.005),
                    Va_lim = (min = -20.0, max = 20.0), Ae = 0.0, Be = 0.0)
            catch
                nothing
            end
            a !== nothing && return (a, :ieeet1)
        end
    end
    return (SEXS(; Ta_Tb = _TYP_SEXS.Ta_Tb, Tb = _TYP_SEXS.Tb, K = _TYP_SEXS.K,
                 Te = _TYP_SEXS.Te, V_lim = _TYP_SEXS.V_lim), :sexs_tip)
end

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
    avr_mode::Symbol = :dsl,    # :dsl (v2, reales) | :sexs | :sexs_wide | :fixed
    gov_mode::Symbol = :dsl,    # :dsl (v2, reales) | :tipico | :sin_hygov | :fixed
)
    by_for, by_loc = load_machine_params(joinpath(raw_dir, dyn_export))
    dsl = (avr_mode == :dsl || gov_mode == :dsl) ?
          load_dsl_params(joinpath(raw_dir, dyn_export)) :
          Dict{String,Dict{String,Dict{String,Float64}}}()
    set_units_base_system!(sys, "NATURAL_UNITS")
    n_full = 0; n_clasico = 0
    conteo_gov = Dict{Symbol,Int}(); conteo_avr = Dict{Symbol,Int}()
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
        modelos_dsl = dom === nothing ? Dict{String,Dict{String,Float64}}() :
                      get(dsl, dom.for_name, Dict{String,Dict{String,Float64}}())
        gov = if gov_mode == :dsl
            g_, tag = _gov_from_dsl(modelos_dsl, categoria)
            conteo_gov[tag] = get(conteo_gov, tag, 0) + 1
            g_
        elseif gov_mode == :fixed
            TGFixed(; efficiency = 1.0)
        elseif gov_mode == :sin_hygov
            _gov_tgov1()
        else
            _es_hidro(categoria) ? _gov_hygov() : _gov_tgov1()
        end

        avr = if avr_mode == :dsl
            a_, tag = _avr_from_dsl(modelos_dsl)
            conteo_avr[tag] = get(conteo_avr, tag, 0) + 1
            a_
        elseif avr_mode == :fixed
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
    (gov_mode == :dsl || avr_mode == :dsl) &&
        @info "Mapeo DSL v2" governors = conteo_gov avrs = conteo_avr
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