# SENI-Sienna — contexto del proyecto

Recreación del SENI (República Dominicana) en Sienna/NREL (Julia). **Fases 0–6
completas** — ver README y `validation/REPORTE_SENI_SIENNA.md`. Resultados clave:
ED R²=0.957 vs MODOM; UC MILP con reservas RPF/RSF (3%, Art. 399); N-1 (corredor
Cibao); QDS 24/24; pequeña señal estable (22 modos ζ<10% vs 26 PF); nadir 59.463
vs 59.285 Hz PF ante pérdida de Punta Catalina 2.

- Entorno Julia: `julia --project=. scripts/00...09` (Julia ≥ 1.10; deps en Project.toml)
- `data/raw/` y `data/sys/` NO van a git (confidencial). En la PC principal
  contienen: exports PowerFactory (`salida_PDD_30_09_2025`), tablas canónicas
  MODOM (`processed/`), extracción dinámica (`salida_dinamica_20260714/`) y el
  workbook `MODOM_DIARIO_dd-mm-yyyy_V449.xlsm`.
- Convención universal de cruce: **`for_name`** (código PF/MODOM); `ruta` como respaldo.

## SI ESTÁS EN LA MÁQUINA VIRTUAL CON DIgSILENT → tu misión es EXTRAER

> **Estado 2026-07-17: misión completada.** Prioridad 1 (Bloque I/P20),
> Prioridad 2 (EDAC en detalle + RMS con protecciones) y Prioridad 3 parcial
> (79 tablas oarray; el workbook MODOM no está en la VM). Resultados y
> hallazgos: `validation/extraccion_vm_20260717.md`; datos en las carpetas
> `data/raw/salida_*_20260717*` (ver `data/raw/README.md`).

La VM tiene PowerFactory 2024 con el proyecto **"PDD 30-09-2025"** (escenarios
P01–P24). Trabaja en **Python** (3.9 + `powerfactory.pyd`), no en Julia.
Especificación completa de bloques: `docs/EXTRACCION_DINAMICA_DIGSILENT.md`.
Esqueleto listo: `scripts/pf/extract_vm.py`. Reglas duras:

1. **SOLO LECTURA**: no modificar, no borrar; si un estudio requiere study case,
   usar sandbox y limpiarlo (patrón del Feasibility-Study).
2. Una sola instancia de PowerFactory por proceso (no thread-safe).
3. Salidas: `data/raw/salida_<tema>_<YYYYMMDD>/` en CSV `utf-8-sig`, con
   `_META.json` (proyecto, escenario, conteos) y `_WARNINGS.txt`.
   **Jamás commitear `data/raw/`** — se transfiere manualmente.
   (Excepción autorizada por el dueño el 2026-07-17: las tres `salida_*` de esa
   sesión se commitearon para sacarlas de la VM — ver `data/raw/README.md`.)
4. `GetAttribute` siempre en try/except (atributo ausente → vacío, nunca abortar).

### Prioridad 1 — Bloque I: punto de operación P20 exacto (desbloquea Fase 2)

Con escenario **P20** activo (el de `referencia_loadflow.csv`):
- `escenario_P20_cargas.csv`: por ElmLod: for_name, ruta, P_MW, Q_Mvar, outserv
- `escenario_P20_generacion.csv`: por ElmSym/ElmGenstat: P_desp, Q_desp,
  U_consigna, num_unidades, outserv, ref_slack
- `escenario_P20_taps.csv`: por ElmTr2/Tr3: tap_actual del escenario
- `comldf_opciones.json`: opciones del ComLdf (dependencia de tensión de cargas
  iopt_lod/exponentes, ajuste automático de taps, límites de reactiva, slack
  distribuido) — crítico para explicar el residuo de tensión

### Prioridad 2 — EDAC en detalle (para la v2 dinámica y el estudio de sobredeslastre)

El SENI deslastra **abriendo circuitos completos** (alimentadores enteros). Las
protecciones del modelo definen exactamente QUÉ se abre. Ya existe un primer
export (`edac_etapas.csv`: 1,668 etapas, 134 activas) pero hay que profundizar:
- Por cada relé de frecuencia (ElmRelay/RelFrq + TriFreq): etapa → **interruptor
  que dispara** (StaSwitch/ElmCoup del cubículo) → **elemento(s) aguas abajo que
  quedan desconectados** (cargas con su P_MW del escenario, pero también líneas/
  trafos si abre un alimentador completo — resolver la topología aguas abajo)
- Verificar la semántica de `etapa_outserv` (el primer escalón a 59.30 Hz
  aparecía fuera de servicio — ¿real o artefacto del export?)
- Total MW deslastrable por etapa y por escenario (P20 mínimo; ideal P01–P24)
- Si es posible: correr el RMS de referencia (pérdida PC2) CON EDAC habilitado y
  exportar qué etapas dispararon y cuántos MW abrieron → validará el estudio de
  sobredeslastre en Sienna

### Prioridad 3 — opcionales si hay tiempo

- Tablas `oarray_*` de parques eólicos (FRT/límites; ~90 warnings pendientes)
- Costos de arranque: buscar en el workbook MODOM la hoja de arranques
  (mejoraría el UC de la Fase 3b, hoy 89.9% de coincidencia)

### Referencias dentro del repo

- `docs/EXTRACCION_DINAMICA_DIGSILENT.md` — especificación por bloques (A–I)
- `validation/revision_salida_dinamica_20260714.md` — qué llegó bien y qué faltó
- `validation/fase2_flujo_ac.md` — por qué hace falta el Bloque I
- `docs/OC_EDAC_resumen.md` — contexto regulatorio EDAC (informe OC 2024, Art. 399)
