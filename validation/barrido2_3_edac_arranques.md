# Barridos 2 y 3 — Sobredeslastre EDAC en PSID y costos de arranque en el UC

## Barrido 2 — Estudio de sobredeslastre EDAC ([scripts/10_edac_sobredeslastre.jl](../scripts/10_edac_sobredeslastre.jl))

**La mala práctica del EDAC del SENI (abrir alimentadores completos), cuantificada
por primera vez en Sienna.**

Diseño: la referencia RMS de PF confirmó que ante la pérdida de Punta Catalina 2
(360 MW) **13 relés de etapa 1 disparan pero el modelo PF no abre nada** (sin
interruptores conectados). Aquí ejecutamos esa acción: Sim A = pérdida de PC2
sin EDAC; Sim B = pérdida de PC2 + apertura de los alimentadores de esos 13
relés en sus tiempos observados (t≈3.20–3.25 s), como `LoadTrip` en PSID.

Mapeo de datos: 13/13 etapas → cargas de Sienna (por loc_name); MW de nuestras
cargas P20 = 501.6 MW vs 494.9 MW de la tabla de la VM ✓ (consistencia 1.4%).

> **CORRECCIÓN (2026-07-19)**: la primera corrida de este estudio tenía un bug
> de unidades (los callbacks de PSID leen getters de PSY → el System debe estar
> en `DEVICE_BASE`; en `NATURAL_UNITS` los deltas quedaban ~100× y producían
> 81 Hz artificiales). Números válidos abajo (corrida corregida, script 11);
> la lectura cualitativa se mantiene, con magnitudes ahora físicas.

| Métrica | Sim A (sin EDAC) | Sim B (con EDAC) |
|---|---|---|
| MW deslastrados | 0 | **501.6** (PVDC solo: 185) |
| Nadir COI | 59.463 Hz | 59.463 Hz (el disparo llega justo en el nadir) |
| Pico de sobrefrecuencia | 60.0 | **60.44 Hz** (t ≈ 5.5 s) |
| f final (30 s) | 59.80 Hz | **60.08 Hz** (queda POR ENCIMA de nominal) |

**Conclusiones (corregidas):**
1. **Ratio de sobredeslastre = 501.6/360 = 1.39×** con solo los 13 relés que
   alcanzan a disparar; el escalón 1 completo (36 etapas activas) abriría
   **1,158 MW = 3.2×** la pérdida.
2. Un evento que se recupera solo con la reserva primaria (Sim A: 59.80 Hz)
   se convierte en **sobrefrecuencia sostenida** (pico 60.44, asentamiento en
   60.08 Hz) que obliga a redespacho de emergencia — con 502 MW de usuarios sin
   servicio innecesariamente. Figura: `figuras/f7_deslastre_selectivo.png`
   (incluye el contrafactual selectivo).
3. El diseño del escalón 1 concentra 185 MW en un solo alimentador (Demanda
   PVDC, con las 6 etapas activas) — el mayor contribuyente individual al
   sobredeslastre.

Salidas: `barrido2_edac_resumen.csv`, `barrido2_edac_aperturas.csv` (relé →
carga → t → MW), series `barrido2_edac_serie_{sin,con}.csv`.

**v2 (siguiente)**: disparo autoconsistente (frecuencia local de Sienna en vez
de los tiempos de PF — requiere calibrar el nadir con los governors reales del
DSL), protecciones de sobrefrecuencia de generación, y escenario de deslastre
"selectivo" para comparar contra el esquema actual.

## Barrido 3 — Costos de arranque en el UC ([scripts/04_uc_milp.jl](../scripts/04_uc_milp.jl))

`e_datgen` (fuente de gen_params) **no contiene C^ARR explícito** aunque el
objetivo de MODOM lo incluye (§6.1 de la transcripción); tampoco e_sets/e_opcn.
Se implementó la estimación de ingeniería **C_ARR = CVP_ef × PMN × TARR**
(combustible del proceso de arranque) en el builder.

| Métrica | start_up = 0 | start_up = estimado |
|---|---|---|
| Coincidencia de commitment | 89.9 % | 89.2 % |
| Costo variable | 159.5 M$ | 160.8 M$ |

**Resultado honesto: neutro.** La brecha de commitment del UC (≈10%) **no la
explican los costos de arranque** — confirma que las unidades extra que MODOM
asegura responden a criterios de seguridad/tensión/AGC (restricciones que el
MILP puro no ve). Palancas siguientes: `must_run` para unidades de seguridad,
derating por disponibilidad horaria, y el C^ARR real si aparece en otra fuente
del OC. La estimación se conserva en el modelo (más realista que 0).
