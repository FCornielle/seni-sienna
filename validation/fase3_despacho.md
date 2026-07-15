# Fase 3a — Despacho económico con commitment fijo vs MODOM

**Estado: META SUPERADA — R² = 0.9566 (meta ≥ 0.94), ENS = 0, OPTIMAL.**

## Formulación ([scripts/03_dispatch_ed.jl](../scripts/03_dispatch_ed.jl))

LP en JuMP + HiGHS sobre los datos del System PSY (≙ Layer 2a de modom-pypsa):

- Commitment horario fijo: unidad encendida ⟺ despacho MODOM > 0 (`modom_generator_dispatch.csv`)
- Térmicos: `pmin·commit ≤ p ≤ pmax·commit`, costo CVP lineal
- Hidro fija = despacho MODOM (decisión de agua, no de costo); renovables ≤ pronóstico
- Red DC por ángulos (717 barras, escalado pu), balance nodal con ENS y vertido a CENS=2×10⁶
- **Flowgates** como restricciones duras (fg1 ≤ 200 MW, fg2 ≤ 670 MW)

## Resultado (24 h, escenario del PDD)

| Métrica | Valor |
|---|---|
| R² despacho térmico unidad-hora (1,872 pares) | **0.9566** |
| ENS | 0 MWh (MODOM reporta 2,866 MWh con su modelo de pérdidas) |
| Costo variable Sienna / MODOM | 221.0 / 263.5 M$ (−16%, sin pérdidas ni arranques aún) |

Detalle por unidad-hora: `fase3_dispatch_comparison.csv`; ENS por barra: `fase3_ens_por_barra.csv`.

## Hallazgos del proceso (importantes para las siguientes fases)

1. **MODOM es un modelo de transporte**: no impone límites térmicos por rama
   individual, solo los flowgates. Con límites por rama el ENS subía a 7,898 MWh
   y el R² caía a 0.913; sin ellos ENS=0 y R²=0.957. `ENFORCE_BRANCH_LIMITS=false`
   es la convención de replicación (validada empíricamente).
2. **Red efectiva ≠ caso base**: 19 ramas marcadas `out_of_service_base_case`
   llevan flujo real en la solución MODOM (hasta 77 MW) → el builder las incluye
   (`_branches_with_modom_flow`). Además, reconexión mínima de islas deficitarias
   (`_reconnect_deficient_islands!`).
3. Escalado numérico: objetivo ×10⁻³ y flujos en pu (HiGHS fallaba con CENS=2×10⁶
   sin escalar: "excessive dual values").

## Brecha de costo restante (−16%)

Esperada en esta capa: MODOM incluye pérdidas (~6% con factores nodales),
costos de arranque y reservas que el LP 2a no modela. Se cierran en:
- Lazo DC↔AC de factores de pérdidas (pendiente, ≙ Layer 4)
- Fase 3b: UC MILP con arranques y reservas RPF/RSF (script 04, PowerSimulations)
