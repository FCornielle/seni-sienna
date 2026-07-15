# Fase 4 — Contingencias N-1 y cuasi-dinámico 24h

**Estado: COMPLETA** — ambos estudios corren de punta a punta sobre el System
físico (export PowerFactory, 718 nodos).

## N-1 ([scripts/05_contingency_n1.jl](../scripts/05_contingency_n1.jl))

Metodología (≙ estudio de contingencias del Feasibility-Study):
1. Flujo base AC (PowerFlows) → flujos y cargabilidad por rama
2. **Screening DC con LODF** (PowerNetworkMatrices): 659 contingencias de
   transmisión (≥ 69 kV) × 803 ramas monitoreadas
3. **Verificación AC completa** en las 10 más críticas
4. Veredicto por deltas: solo cuentan sobrecargas **nuevas** respecto al caso base

Resultados (escenario pico nocturno del export):
- **0 contingencias con islanding** (la fusión node-breaker elimina radiales espurios)
- **49 contingencias producen sobrecargas nuevas** en DC
- Top críticas: el corredor 138 kV del Cibao — **Canabacoa–Moca (13 sobrecargas
  nuevas en AC), Moca–Salcedo (10), Salcedo–SFM (7), trafo SFM 138/69 (8)** —
  consistente con la debilidad conocida de la zona norte
- 5 de las 10 críticas no convergen en AC post-contingencia: severidad real
  (colapso de tensión local) amplificada porque el modelo no reajusta taps ni
  conmuta capacitores tras la contingencia

Detalle: `fase4_n1_screening.csv` (659 filas), `fase4_n1_ac.csv`.

## Cuasi-dinámico 24h ([scripts/06_quasi_dynamic_24h.jl](../scripts/06_quasi_dynamic_24h.jl))

Bucle de 24 flujos AC con el perfil horario de demanda del SENI (capa canónica
MODOM), cargas y generación despachable escaladas por el factor horario del
sistema (slack en Punta Catalina absorbe el residuo y las pérdidas).

- **24/24 horas convergen**
- Patrón físico correcto: tensiones mínimas en el pico nocturno (h20–22,
  v_min ≈ 0.81) y máximas en el valle (h4–8, hasta 1.11 en barras con
  capacitores fijos y poca carga)
- Salidas: `fase4_qds_resumen.csv` (por hora) y `fase4_qds_tensiones.csv`
  (perfil completo por barra ≥ 69 kV: 24 × ~450 barras)

## Aproximaciones documentadas (v1)

1. **Escalado proporcional del punto de operación** por hora: el despacho y la
   demanda nodal exacta por hora requieren la inyección por `for_name` del
   despacho MODOM (patrón ac_inject de modom-pypsa) o el Bloque I de la VM —
   siguiente refinamiento natural, compartido con la Fase 2
2. Taps fijos del escenario exportado y capacitores sin conmutación horaria →
   sobretensiones de valle exageradas (en la realidad la operación desconecta
   capacitores/ajusta taps en el valle)
3. El conteo de tensiones fuera de banda en N-1 es absoluto (no delta vs base);
   el veredicto delta aplica hoy solo a sobrecargas
