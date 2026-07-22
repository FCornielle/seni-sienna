# Gaps de implementación — plan de cierre

Clasificación por lo que se necesita para cerrarlos. **Tipo A en curso**; B/C/D
almacenados aquí para abordarlos después de cerrar A.

## A — Cierro yo solo (solo tiempo, sin datos externos)  ← EN CURSO
| Gap | Qué hago | Estado |
|---|---|---|
| must-run en el UC | Unidades siempre ON en MODOM → `must_run=true` | ✅ commitment 89.9→**93.9%**, R² 0.72→**0.93** |
| Lazo de pérdidas DC (eq. 29-30) | pérdidas P=r·f² por rama, 50/50 a barras, re-solve caliente | ✅ costo −16%→**−2.8%**, R² 0.957→**0.971** |
| v2 dinámica: inversores WECC | `DynamicInverter` (REGC/REEC/REPC) para PV/eólica/BESS | pendiente (esfuerzo focalizado) |
| v2 dinámica: GGOV1 real | Modelo custom en Julia (PSID 0.15 no inicializa GeneralGovModel) | pendiente (esfuerzo focalizado) |
| NAMX (nº máx arranques) | Σ start ≤ NAMX como extra_functionality de PSI | pendiente (custom PSI; NAMX sí está en gen_params) |
| Empaquetado + UX | `create_app`, animación horaria del mapa, selector P01–P24 | pendiente |

> **Nota de pérdidas**: el efectivo ~9% es algo mayor al físico (~5-6%) porque
> absorbe también el uplift OPLM de MODOM y el efecto de costo marginal; por eso
> el costo queda tan cerca (−2.8%). El loop nodal exacto (mapeo al System físico
> AC) sería el refinamiento fino.

## B — Necesitan un DATO de la VM / OC (extracción)
- **AGC como reserva separada** (eq. 14-15): `gen_params` no tiene columna de
  participación/límite AGC → necesita la lista de unidades AGC del OC. (Hoy su
  margen queda absorbido en la RSF.)
- **Shunts/SVC por escenario**: `paso_actual` de ElmShnt + consigna SVC en P20 → cierra el residuo 0.04 pu del radial Este (Fase 2).
- **Costos de arranque C^ARR**: no están en el workbook; buscar en otra declaración del OC o estimar por combustible de arranque.
- **oarray_* FRT de plantas solares**: la API de PF no las lee → copiar a mano desde la GUI.
- **Embalses (RENDH, aportes, niveles)**: del **PSD semanal** del Dropbox del OC.
- **Puntos de operación P01–P24**: para validar despacho hora a hora y R² por escenario.

## C — Sienna NO puede (otra herramienta)
- **Cortocircuito IEC 60909**: mantener pandapower (`calc_sc`) / PowerFactory (flujo híbrido).
- **Coordinación de protecciones/relés**: fuera de alcance.

## D — Validación (necesitan referencia)
- Comparación cuantitativa vs despacho real del OC (PDD `Despacho en OM`, varios días).
- Match modo-por-modo de pequeña señal vs PowerFactory (más escenarios).
