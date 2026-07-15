# Especificación: extracción de datos dinámicos desde DIgSILENT PowerFactory

**Propósito**: brief para el agente que trabajará en la **máquina virtual con PowerFactory 2024** y el proyecto **"PDD 30-09-2025"**. Debe generar scripts Python (API `powerfactory`) que exporten todo lo necesario para que Sienna (`PowerSimulationsDynamics.jl`) pueda correr **pequeña señal** y **transitorios RMS** del SENI (Fase 5 del plan).

**Regla de oro**: extracción de **solo lectura** — no modificar el proyecto, no crear objetos, no borrar (mismo patrón sandbox del Feasibility-Study). Clave de cruce en todos los archivos: **`for_name`** (y `ruta` como respaldo cuando `for_name` esté vacío).

---

## 0. Lo que YA está extraído (no repetir)

El export existente (`salida_PDD_30_09_2025/todos_los_elementos/`) ya incluye:

| Archivo | Contenido útil |
|---|---|
| `TypSym.csv` | **Parámetros eléctricos completos de máquina**: `sgn, cosn, ugn, xd, xq, xl, rstr, xds, xqs, xdss, xqss, xdsat, tds0, tdss0, tqss0, h, iturbo` |
| `ElmSym.csv` | Máquinas: barra, `typ_id`, `ngnum`, `pgini, qgini, usetp, av_mode, ip_ctrl`, límites |
| `ElmGenstat.csv` | Inversores: barra, `sgn, cosn, pgini, qgini, usetp, av_mode`, límites |
| `TypLod.csv` | Dependencia de tensión de cargas: `aP,bP,cP,aQ,bQ,cQ,kpu,kqu` |
| `ElmDsl.csv`, `ElmComp.csv`, `RelFrq.csv`, `TriFreq.csv`, `ElmStactrl.csv` | **Solo metadatos** (nombre/ruta/typ_id) — SIN parámetros ni composición → esto es lo que falta |

---

## 1. BLOQUE A — Composición de frames por máquina (`frames_slots.csv`)

Para cada `ElmSym` y cada `ElmGenstat` con modelo dinámico:

1. Obtener su **composite model** (`c_pmod` → `ElmComp`).
2. Del `ElmComp`: nombre del **frame** (`typ_id` → `BlkDef` del frame) y el arreglo de **slots** (`pblk` = definiciones de slot, `pelm` = elemento asignado a cada slot).

**Columnas**: `maquina_for_name, maquina_clase (ElmSym|ElmGenstat), comp_loc_name, comp_for_name, frame_name, slot_idx, slot_name, elemento_loc_name, elemento_for_name, elemento_clase (ElmDsl|ElmSym|StaVmea|...), elemento_ruta`

Esto nos dice qué AVR/GOV/PSS/PLL/controlador tiene cada máquina y en qué slot.

## 2. BLOQUE B — Parámetros de TODOS los DSL (`dsl_parametros.csv`) ⚠️ el más importante

Para cada `ElmDsl` del proyecto (usar `app.GetCalcRelevantObjects("*.ElmDsl")` y complementar con búsqueda en la librería del proyecto):

1. Identificar el **model definition** (`typ_id` → `BlkDef`): `model_name = typ_id.loc_name` (p. ej. `avr_SEXS`, `gov_TGOV1`, `pss_STAB1`, modelos WECC `REGC_A/REEC_B/REPC_A`, o DSL propietarios).
2. Extraer la **lista de nombres de parámetros** del `BlkDef` (atributo `sParams`; si viene vacío, iterar la definición) y el **valor** de cada parámetro leyéndolo del `ElmDsl` con `GetAttribute(nombre)`. Los parámetros vectoriales/matriciales (`ChaVec`, `IntMat` referenciados) se exportan aplanados `nombre[idx]`.

**Formato largo**: `dsl_for_name, dsl_loc_name, dsl_ruta, model_name, frame_owner_for_name, param_name, param_value`

Incluir también los DSL de plantas renovables/BESS (P_Control, Q_Control, PLL, FRT, etc. — ya vimos `P_Control` en Planta_Monte Plata Solar).

## 3. BLOQUE C — Complemento de máquinas síncronas (`sym_extra.csv`)

Del `TypSym` faltan en el export actual (extraer si el atributo existe; si no, dejar vacío):

- `tqs0` (T'q0 — el export tiene tds0/tdss0/tqss0 pero no T'q0)
- `dpu` / `dkd` (amortiguamiento D), `xrl`, `satur`/`sg10`/`sg12` (saturación — solo hay `xdsat`)
- `J` o constante de aceleración alternativa si `h` viene en 0
- Del `ElmSym`: `iv_mode`, referencia del **frame** (`c_pmod.loc_name`), y si es **referencia/slack** del escenario

**Columnas**: `typ_for_name, tqs0, dpu, sg10, sg12, xrl, ...` + `sym_for_name, c_pmod_for_name, es_slack`

## 4. BLOQUE D — Inversores / generadores estáticos (`genstat_dinamica.csv`)

Para cada `ElmGenstat` (PV, eólica, BESS):

- **Modelo dinámico usado en RMS**: atributo del modelo (`iSimModel` — constante de corriente / plantilla / DSL), y si tiene composite model → ya sale en Bloques A/B
- Curvas/ajustes **FRT** (low/high voltage ride-through) si existen en el modelo o plantilla
- Límites dinámicos: `Iqmin/Iqmax`, prioridad P/Q durante falla (`Fmode`/atributos equivalentes de la plantilla)
- Categoría (`cCategory`: Photovoltaic/Wind/Storage) y `scale0`

## 5. BLOQUE E — Controladores de estación (`stactrl.csv`)

Para cada `ElmStactrl`: modo de control (`i_ctrl`: V/Q/cosφ), `usetp`, `qsetp`, droop/estatismo (`ddroop`), barra controlada (`p_cub`/`rembar`), y **lista de generadores controlados** (`psym`) con su `for_name`.

## 6. BLOQUE F — EDAC / deslastre por baja frecuencia (`edac_etapas.csv`) ⚠️ crítico para el nadir 59.2 Hz

Recorrer relés de frecuencia: `ElmRelay` con bloques `RelFrq`/`TypFrq` y disparadores `TriFreq`:

- Por etapa: **frecuencia de arranque (Hz)**, **retardo (s)**, df/dt si aplica, y el **objeto disparado** (interruptor/carga → resolver la carga `ElmLod` con su `for_name` y P_MW del escenario)
- Estado (`outserv`) y ubicación (barra/subestación)

**Columnas**: `relay_for_name, etapa, f_arranque_hz, dfdt, retardo_s, carga_for_name, carga_P_MW, barra_for_name, outserv`

Con esto Sienna modela el EDAC como deslastre por pasos en PSID.

## 7. BLOQUE G — SVC y compensación dinámica (`svc_dinamica.csv`)

Para cada `ElmSvs`: modo de control, consigna, límites `Q_min/Q_max` (ya están estáticos), ganancia/constantes de tiempo del regulador si tiene modelo dinámico o DSL asociado (→ Bloques A/B).

## 8. BLOQUE H — Resultados de referencia para validar Sienna

Sobre el escenario de referencia (usar **P20**, demanda máxima, y anotar cuál se usó):

1. **Pequeña señal**: correr análisis modal (`ComMod`) y exportar TODOS los modos: `referencia_small_signal.csv` con `parte_real, parte_imag, frecuencia_hz, amortiguamiento_pct, magnitud_participacion_top3, maquinas_top3`
2. **RMS de referencia**: simulación con **pérdida del mayor generador en línea** (identificarlo del despacho del escenario): exportar `referencia_rms_frecuencia.csv` con `t_s, f_coi_hz, f_barras_clave` (paso ≤ 10 ms, 30 s) y `referencia_rms_tensiones.csv` con tensiones de 5–10 barras 138/345 kV
3. **Flujo de carga del escenario**: `referencia_loadflow.csv` (barra, V_pu, ángulo) — para inicializar/validar la Fase 2

## 8-bis. BLOQUE I — Punto de operación exacto del escenario (pendiente, para Fase 2)

La validación del flujo AC detectó que el export `salida_PDD_*` fue tomado con un
escenario distinto a P20 (demanda 3,645 vs 3,466 MW). Con el **mismo escenario y
study case** usados para `referencia_loadflow.csv`, exportar:

1. `escenario_P20_cargas.csv`: por carga (`for_name`, `ruta`): `P_MW, Q_Mvar, outserv`
2. `escenario_P20_generacion.csv`: por generador síncrono y estático: `P_desp_MW,
   Q_desp_Mvar, U_consigna_pu, num_unidades, outserv, ref_slack`
3. `escenario_P20_taps.csv`: por trafo 2/3 devanados: `tap_actual` (posición del escenario)
4. `comldf_opciones.json`: opciones del `ComLdf` usado en la referencia: dependencia
   de tensión de cargas (iopt_lod / voltage dependency ON-OFF y exponentes), ajuste
   automático de taps, cumplimiento de límites de reactiva, slack distribuido

## 9. Metadatos (`_META.json`)

`proyecto, escenario_activo, fecha_extraccion, version_pf, conteos por clase, hash/fecha del PDD`.

---

## Instrucciones operativas para el agente (VM)

1. **Entorno**: Python 3.9 + `powerfactory.pyd` (mismo patrón que `Feasibility-Study/pf_worker/connect.py`: una sola instancia de PowerFactory por proceso, no thread-safe).
2. Activar proyecto **"PDD 30-09-2025"** y el escenario indicado (default P20). No modificar nada; si un estudio de referencia (Bloque H) requiere crear un study case, usar sandbox y limpiarlo al final (patrón del Feasibility-Study).
3. **Salida**: carpeta `salida_dinamica_<YYYYMMDD>/` con los CSVs de arriba, UTF-8 con BOM (`utf-8-sig`), separador coma, y `_META.json`. Comprimir y traer a este proyecto → `data/raw/`.
4. **Robustez**: `GetAttribute` dentro de try/except (atributos que no existen en todas las versiones → valor vacío, nunca abortar); log de advertencias por objeto en `_WARNINGS.txt`.
5. Los objetos fuera de servicio (`outserv=1`) también se exportan (marcados) — la selección se hace en Sienna.
6. Verificación mínima antes de entregar: nº de máquinas con frame ≥ nº de máquinas grandes (>20 MW); ningún `dsl_parametros.csv` vacío; EDAC con ≥ 1 etapa si el proyecto la modela.

## Destino en Sienna (para contexto del agente)

| Bloque | Uso en PSID |
|---|---|
| TypSym + C | `DynamicGenerator`: máquina (GENROU/GENSAL según `iturbo`), shaft, base |
| A + B (AVR/GOV/PSS) | Mapeo a modelos estándar PSID (SEXS, EXST1, TGOV1, HYGOV, IEEEST…) o custom Julia si es DSL propietario |
| D + B (inversores) | `DynamicInverter` (WECC REGC/REEC/REPC genéricos) |
| E | Control de planta (REPC / droop de tensión) |
| F | Deslastre EDAC por pasos (perturbaciones condicionadas) |
| H | Validación: modos y nadir Sienna vs PowerFactory |
