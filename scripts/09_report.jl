# Fase 6 — Reporte consolidado del proyecto SENI-Sienna: figuras + veredictos
# del Código de Conexión aplicados a los resultados de las Fases 2–5.
# Salidas: validation/figuras/*.png y validation/REPORTE_SENI_SIENNA.md

using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
ENV["GKSwstype"] = "100"   # GR sin display (headless)
using Plots, CSV, DataFrames, Statistics
using SeniSienna

val_dir = joinpath(@__DIR__, "..", "validation")
fig_dir = joinpath(val_dir, "figuras")
mkpath(fig_dir)

# Paleta fija (2 series + umbral): azul = Sienna, gris oscuro = referencia,
# rojo reservado para límites/estado. Marcas finas, un solo eje por figura.
const C_SIENNA = "#4269d0"
const C_REF = "#5b5b66"
const C_LIM = "#c8474b"
default(; fontfamily = "sans-serif", linewidth = 2, framestyle = :box,
        grid = :y, gridalpha = 0.15, legend = :topright, dpi = 150,
        foreground_color_legend = nothing)

# ---- F1: despacho térmico Sienna vs MODOM (dispersión unidad-hora) -----------
cmp3 = CSV.read(joinpath(val_dir, "fase3_dispatch_comparison.csv"), DataFrame)
lim = maximum([cmp3.modom; cmp3.sienna])
p1 = scatter(cmp3.modom, cmp3.sienna; color = C_SIENNA, markersize = 3,
             markerstrokewidth = 0, alpha = 0.55, label = "unidad-hora (1,872)",
             xlabel = "Despacho MODOM (MW)", ylabel = "Despacho Sienna (MW)",
             title = "Fase 3a — ED con commitment fijo (R² = 0.957)")
plot!(p1, [0, lim], [0, lim]; color = C_REF, linestyle = :dash, label = "y = x")
savefig(p1, joinpath(fig_dir, "f1_despacho_vs_modom.png"))

# ---- F2: demanda servida por hora, MODOM vs Sienna ----------------------------
tot = combine(groupby(cmp3, :hora), :modom => sum => :modom, :sienna => sum => :sienna)
p2 = plot(tot.hora, tot.modom; color = C_REF, label = "MODOM",
          xlabel = "Hora", ylabel = "Generación térmica (MW)",
          title = "Fase 3a — Térmica total por hora")
plot!(p2, tot.hora, tot.sienna; color = C_SIENNA, label = "Sienna")
savefig(p2, joinpath(fig_dir, "f2_termica_horaria.png"))

# ---- F3: envolvente de tensiones del cuasi-dinámico 24h -----------------------
qds = CSV.read(joinpath(val_dir, "fase4_qds_resumen.csv"), DataFrame)
p3 = plot(qds.hora, qds.v_min; color = C_SIENNA, label = "V mínima",
          xlabel = "Hora", ylabel = "Tensión (pu)",
          title = "Fase 4 — Envolvente de tensión 24h (barras ≥ 69 kV)")
plot!(p3, qds.hora, qds.v_max; color = C_SIENNA, linestyle = :dot, label = "V máxima")
hline!(p3, [0.95, 1.05]; color = C_LIM, linestyle = :dash, label = "banda ±5%")
savefig(p3, joinpath(fig_dir, "f3_qds_envolvente.png"))

# ---- F4: respuesta de frecuencia (pérdida Punta Catalina 2) -------------------
frec = CSV.read(joinpath(val_dir, "fase5_rms_frecuencia_sienna.csv"), DataFrame)
p4 = plot(frec.t_s, frec.f_coi_hz; color = C_SIENNA, label = "f COI Sienna",
          xlabel = "Tiempo (s)", ylabel = "Frecuencia (Hz)",
          title = "Fase 5 — Pérdida de Punta Catalina 2 (360 MW)")
hline!(p4, [59.285]; color = C_REF, linestyle = :dash, label = "nadir PowerFactory")
hline!(p4, [59.2]; color = C_LIM, linestyle = :dash, label = "criterio 59.2 Hz")
savefig(p4, joinpath(fig_dir, "f4_frecuencia_pc2.png"))

# ---- F5: ranking N-1 (top 10 por sobrecargas nuevas) --------------------------
scr = CSV.read(joinpath(val_dir, "fase4_n1_screening.csv"), DataFrame)
top = first(sort(scr, :sobrecargas_nuevas, rev = true), 10)
corto(s) = length(s) > 30 ? first(s, 28) * "…" : s  # first(): seguro con UTF-8
etiquetas = reverse([corto(String(c)) for c in top.contingencia])
ys = 1:nrow(top)
p5 = bar(ys, reverse(top.sobrecargas_nuevas);
         orientation = :h, yticks = (ys, etiquetas),
         color = C_SIENNA, linecolor = :transparent, bar_width = 0.55, label = "",
         xlabel = "Sobrecargas nuevas (screening DC)",
         title = "Fase 4 — Contingencias N-1 críticas",
         left_margin = 24Plots.mm, bottom_margin = 8Plots.mm, size = (900, 450))
savefig(p5, joinpath(fig_dir, "f5_n1_ranking.png"))

# ---- veredictos ---------------------------------------------------------------
ss = CSV.read(joinpath(val_dir, "fase5_small_signal_sienna.csv"), DataFrame)
vn = veredicto_nadir(minimum(frec.f_coi_hz))
va = veredicto_amortiguamiento(ss, ss)  # base = caso (línea base del proyecto)

# ---- reporte ------------------------------------------------------------------
r2_3a = round(1 - sum((cmp3.modom .- cmp3.sienna) .^ 2) /
                  sum((cmp3.modom .- mean(cmp3.modom)) .^ 2); digits = 4)
uc = CSV.read(joinpath(val_dir, "fase3b_uc_comparison.csv"), DataFrame)
uc_match = round(100 * count(uc.modom_on .== uc.sienna_on) / nrow(uc); digits = 1)
dv = CSV.read(joinpath(val_dir, "fase2_delta_v.csv"), DataFrame)
dv69 = dv[dv.kv .>= 69.0, :]

reporte = """
# REPORTE CONSOLIDADO — SENI en Sienna (NREL)

Generado por `scripts/09_report.jl`. Figuras en `validation/figuras/`.

## Resultados por fase

| Fase | Métrica clave | Resultado | Referencia |
|---|---|---|---|
| 2 — Flujo AC | \\|ΔV\\| medio ≥69 kV | $(round(mean(abs.(dv69.dv)); digits = 4)) pu | PowerFactory P20 (meta 0.005, pendiente Bloque I) |
| 3a — Despacho ED | R² unidad-hora | **$(r2_3a)** | MODOM (meta ≥ 0.94 ✅) |
| 3b — UC MILP | Coincidencia commitment | $(uc_match) % | MODOM (sin costos de arranque) |
| 3b — Reservas | RPF y RSF co-optimizadas | 3% demanda/h ✅ | Art. 399 / PMP OC 2026-27 |
| 4 — N-1 | Contingencias con sobrecargas nuevas | $(count(scr.sobrecargas_nuevas .> 0)) de $(nrow(scr)) | corredor Cibao 138 kV |
| 4 — QDS 24h | Horas convergidas | $(count(qds.convergio))/24 | — |
| 5 — Pequeña señal | Modos EM ζ<10% | $(count((ss.frecuencia_hz .> 0.1) .& (ss.frecuencia_hz .< 3.0) .& (ss.amortiguamiento_pct .< 10))) | 26 en PowerFactory |
| 5 — Frecuencia | Nadir COI (PC2, 360 MW) | **$(round(minimum(frec.f_coi_hz); digits = 3)) Hz** | 59.285 Hz PF |

## Veredictos (Código de Conexión)

- **Frecuencia**: nadir $(round(minimum(frec.f_coi_hz); digits = 3)) Hz →
  $(vn.cumple ? "CUMPLE" : "NO CUMPLE") el piso de 59.2 Hz (margen $(vn.margen_hz) Hz).
  ¿Activaría EDAC (escalones desde 59.3 Hz)? $(vn.activa_edac ? "SÍ" : "NO").
- **Amortiguamiento**: ζ mínimo banda EM = $(round(va.zeta_min_caso; digits = 2)) % —
  línea base del proyecto para veredictos por delta en estudios de interconexión.
- Funciones reutilizables en `src/verdicts.jl`: tensión, sobrecargas,
  amortiguamiento y nadir, todas con lógica de deltas (solo cuenta lo
  introducido o empeorado).

## Nota EDAC (contexto operativo SENI)

Ante la salida de un gran generador (p. ej. Punta Catalina), el SENI opera el
EDAC **abriendo circuitos completos** (alimentadores enteros con toda su carga
mezclada). Es una práctica gruesa: sobredeslastra y no discrimina carga
crítica. Referencias: informe OC "Actualización Esquema EDAC del SENI" (2024,
citado en docs/OC_EDAC_resumen.md) y PMP Jul2026–Jun2027 (análisis de
frecuencia "en proceso de adecuación"; reservas RPF/RSF = 3% de la demanda,
Art. 399). El modelo tiene las **134 etapas EDAC activas** extraídas
(edac_etapas.csv) listas para la v2 dinámica — permitirá cuantificar el
sobredeslastre de la práctica actual vs esquemas selectivos.

## Gaps fuera del alcance de Sienna (flujo híbrido)

- **Cortocircuito IEC 60909**: mantener PowerFactory/pandapower (`calc_sc`).
- **Protecciones/relés**: fuera de alcance.

## Figuras

![Despacho vs MODOM](figuras/f1_despacho_vs_modom.png)
![Térmica horaria](figuras/f2_termica_horaria.png)
![Envolvente QDS](figuras/f3_qds_envolvente.png)
![Frecuencia PC2](figuras/f4_frecuencia_pc2.png)
![Ranking N-1](figuras/f5_n1_ranking.png)
"""
write(joinpath(val_dir, "REPORTE_SENI_SIENNA.md"), reporte)
println("Reporte y ", length(readdir(fig_dir)), " figuras generadas en validation/")
