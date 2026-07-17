# Fase 6 — Funciones de veredicto reutilizables (Código de Conexión, Ley 125-01).
# Lógica de deltas del Feasibility-Study: una condición solo cuenta si es
# INTRODUCIDA o EMPEORADA respecto al caso base.

"""
    veredicto_tension(v_base, v_caso; banda=(0.95, 1.05))

Compara tensiones por barra (Dict nombre→V_pu) entre caso base y caso de
estudio. Devuelve (cumple, nuevas, empeoradas, detalle).
"""
function veredicto_tension(v_base::AbstractDict, v_caso::AbstractDict;
                           banda::Tuple{Float64,Float64} = (0.95, 1.05))
    fuera(v) = v < banda[1] || v > banda[2]
    exceso(v) = max(banda[1] - v, v - banda[2], 0.0)
    nuevas = String[]; empeoradas = String[]
    for (bus, v) in v_caso
        haskey(v_base, bus) || continue
        vb = v_base[bus]
        if fuera(v) && !fuera(vb)
            push!(nuevas, bus)
        elseif fuera(v) && exceso(v) > exceso(vb) + 1e-4
            push!(empeoradas, bus)
        end
    end
    return (cumple = isempty(nuevas) && isempty(empeoradas),
            nuevas = nuevas, empeoradas = empeoradas)
end

"""
    veredicto_sobrecargas(carga_base, carga_caso; limite=100.0)

Compara cargabilidad por rama (Dict nombre→%) base vs caso.
Solo cuentan sobrecargas nuevas o empeoradas.
"""
function veredicto_sobrecargas(carga_base::AbstractDict, carga_caso::AbstractDict;
                               limite::Float64 = 100.0)
    nuevas = String[]; empeoradas = String[]
    for (rama, c) in carga_caso
        haskey(carga_base, rama) || continue
        cb = carga_base[rama]
        if c > limite && cb <= limite
            push!(nuevas, rama)
        elseif c > limite && c > cb + 0.5
            push!(empeoradas, rama)
        end
    end
    return (cumple = isempty(nuevas) && isempty(empeoradas),
            nuevas = nuevas, empeoradas = empeoradas)
end

"""
    veredicto_amortiguamiento(modos_base, modos_caso; zeta_min=5.0, banda_hz=(0.1, 3.0))

Compara modos electromecánicos (DataFrames con frecuencia_hz y
amortiguamiento_pct). Falla si el caso reduce el ζ mínimo de la banda EM o
introduce modos con ζ < zeta_min que no existían.
"""
function veredicto_amortiguamiento(modos_base, modos_caso;
                                   zeta_min::Float64 = 5.0,
                                   banda_hz::Tuple{Float64,Float64} = (0.1, 3.0))
    en_banda(df) = df[(df.frecuencia_hz .> banda_hz[1]) .&
                      (df.frecuencia_hz .< banda_hz[2]), :]
    b, c = en_banda(modos_base), en_banda(modos_caso)
    ζb = isempty(b.amortiguamiento_pct) ? Inf : minimum(b.amortiguamiento_pct)
    ζc = isempty(c.amortiguamiento_pct) ? Inf : minimum(c.amortiguamiento_pct)
    criticos_b = count(b.amortiguamiento_pct .< zeta_min)
    criticos_c = count(c.amortiguamiento_pct .< zeta_min)
    return (cumple = ζc >= ζb - 0.1 && criticos_c <= criticos_b,
            zeta_min_base = ζb, zeta_min_caso = ζc,
            criticos_base = criticos_b, criticos_caso = criticos_c)
end

"""
    veredicto_nadir(f_nadir_hz; limite=59.2, primer_escalon_edac=59.3)

Criterio de frecuencia del Código de Conexión: nadir sobre el primer escalón
EDAC (59.2 Hz como piso regulatorio). Reporta además si el evento activaría
etapas EDAC del esquema vigente (≥ 59.3 Hz de arranque en el modelo PDD).

Nota SENI: el EDAC del SENI deslastra ABRIENDO CIRCUITOS COMPLETOS
(alimentadores enteros, con toda su carga mezclada) — práctica reconocida como
gruesa: sobredeslastra y no discrimina carga crítica. El informe del OC
"Actualización Esquema EDAC del SENI" (2024) y el PMP Jul2026–Jun2027 (análisis
de frecuencia "en proceso de adecuación") lo confirman como área en revisión.
"""
function veredicto_nadir(f_nadir_hz::Float64;
                         limite::Float64 = 59.2,
                         primer_escalon_edac::Float64 = 59.3)
    return (cumple = f_nadir_hz >= limite,
            activa_edac = f_nadir_hz < primer_escalon_edac,
            margen_hz = round(f_nadir_hz - limite; digits = 3))
end
