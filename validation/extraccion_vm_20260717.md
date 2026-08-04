# Extracción VM 2026-07-17 — Bloque I (P20) + EDAC en detalle

**Entorno**: VM con PowerFactory 2024, proyecto "PDD 30-09-2025", escenario **P20**,
study case **BASE**, Python 3.9 + `powerfactory.pyd`. Script: `scripts/pf/extract_vm.py`
(solo lectura; el barrido P01–P24 solo activa escenarios y los restaura a P20).

**Salida**: `data/raw/salida_bloqueI_edac_20260717_111009/` (no versionada — transferir
manualmente a la PC principal).

## Prioridad 1 — Bloque I (desbloquea Fase 2)

| Archivo | Contenido | Verificación |
|---|---|---|
| `escenario_P20_cargas.csv` | 442 cargas (370 activas), P/Q/escala/outserv | ΣP activas = **3,624.3 MW** |
| `escenario_P20_generacion.csv` | 157 unidades (86 activas), P/Q/U_consigna/ngnum/ref_slack | ΣP desp = 3,625.5 MW; slack = Punta Catalina 1 |
| `escenario_P20_taps.csv` | 184 trafos, posición de tap del escenario | 106 con tap ≠ 0 (coincide con Fase 2) |
| `comldf_opciones.json` | opciones del ComLdf del study case BASE | ver hallazgos ↓ |

**Hallazgos clave del ComLdf** (explican parte del residuo de la Fase 2):

- `iopt_pq = 0` → **sin dependencia de tensión de cargas** (potencia constante,
  igual que nuestro modelo — descarta la hipótesis 2 del diagnóstico).
- `iopt_at = 0` → sin ajuste automático de taps (los taps del escenario son fijos ✓).
- `iopt_lim = 1`, `iopt_plim = 1` → **límites de reactiva/activa activos** en la
  referencia (hipótesis 4 confirmada: hay que aplicar `check_reactive_power_limits`).
- `iPbalancing = 0` → balance por máquina de referencia (sin slack distribuido).
- `iopt_asht = 1` → ajuste de shunts conmutables activo.

**Sobre la demanda**: P20 activo suma 3,624 MW "crudos" (Σ plini en servicio).
Los escenarios pico suman P21 = 3,644 / P23 = 3,645 MW → la demanda 3,645 MW del
export `salida_PDD_*` coincide con **P21/P23**, lo que confirma el diagnóstico de
desalineación de escenario de la Fase 2. La cifra 3,466 MW citada antes para P20
no es la suma cruda de `plini` (revisar en la PC principal qué filtro se aplicó).

## Prioridad 2 — EDAC en detalle

Archivos: `edac_detalle.csv` (1,668 etapas RelFrq, una fila por etapa),
`edac_aguas_abajo.csv` (5,088 filas etapa → elemento desconectado),
`edac_mw_por_escenario.csv` (MW deslastrable por etapa × P01–P24),
`escenarios_demanda.csv` (demanda total por escenario).

Método: cadena de padres del relé → cubículo raíz → `obj_id` (objeto disparado);
grafo de conectividad (5,084 terminales; aristas = ramas en servicio con cubículos
cerrados) y BFS: al abrir la rama, todo componente que pierde el camino al slack
(Punta Catalina 1) queda "aguas abajo". Cargas y generadores del componente se
listan con su P del escenario.

### Respuestas a las preguntas del CLAUDE.md

1. **Semántica de `etapa_outserv`**: es **real, no artefacto** — es la asignación
   de cada alimentador a su(s) escalón(es). Cada relé de 6 etapas tiene fuera de
   servicio las etapas que no le corresponden (p. ej. MONTE PLATA solo activa
   EDE 2 a 59.2 Hz; DESPACHO activa EDE 4–6). El primer escalón (59.30 Hz) **sí
   está activo en 36 etapas** del sistema (134 etapas activas en total, igual que
   el export previo).
2. **Qué abre cada etapa**: de las 134 etapas activas, 121 disparan una carga
   (`ElmLod`) directamente, 7 abren líneas (con su componente aguas abajo
   resuelto) y 6 están en cubículos sin `obj_id` (protecciones de trafo/máquina —
   listadas en `_WARNINGS.txt`). Solo 9 cubículos tienen `StaSwitch` explícito;
   en el resto el "interruptor" es la apertura del elemento en su cubículo.
3. **MW por etapa (P20, etapas activas)**:

   | Escalón | MW |
   |---|---|
   | 59.3 Hz | 1,158 |
   | 59.2 Hz | 515 |
   | 59.1 Hz | 858 |
   | 59.0 Hz | 427 |
   | 58.9 Hz | 520 |
   | 58.8 Hz | 796 |
   | 58.7 Hz | 128 |

   Nota: PVDC (Demanda PVDC, 185 MW) tiene las **6 etapas activas** (59.3–58.8),
   con lo que dispara ya en el primer escalón. Hay además relés dF/dt
   (−2 Hz/s, p. ej. DESPACHO dF/dt, HAINAMOSA 138 dF/dt) exportados con su
   `dfdt_hz_s`.
4. **Por escenario**: `edac_mw_por_escenario.csv` cubre P01–P24 (demandas de
   2,895 a 3,655 MW). Los conjuntos aguas abajo se resolvieron con la topología
   de P20; entre escenarios solo cambia P/outserv de cada carga (limitación
   anotada en `_WARNINGS.txt`).

### RMS de referencia con EDAC habilitado — hallazgo principal

`data/raw/salida_rms_edac_20260717_113111/` — pérdida de Punta Catalina 2
(360 MW) a t = 1 s, escenario P20, RMS 30 s a 10 ms, protecciones activas,
study case sandbox (borrado al final; script `scripts/pf/rms_edac_vm.py`).

- **Nadir 59.285 Hz en t ≈ 3.28 s** (barras 345 kV; idéntico a la referencia
  previa) y recuperación a 59.84 Hz en t = 30 s.
- **13 relés EDAC de etapa 1 SÍ disparan** entre t = 3.20 y 3.25 s (59.30 Hz
  + 0.1 s): SAN JUAN, BARAHONA, KILOMETRO 10.5 B, EMBAJADOR, UASD 138,
  VILLA DUARTE 138, PVDC MINA, ZF SANTIAGO, CANABACOA, PUERTO PLATA,
  HIGUEY 138, LA ROMANA 138, SAN PEDRO DE MACORIS
  (`rms_edac_disparos_reles.csv`).
- **Pero 0 MW se abren**: la única "Circuit-Breaker Action" de toda la
  simulación es el propio evento de PC2. Las señales de disparo van "to the
  connected breaker(s)" y **no hay interruptores conectados** (solo 9 de 308
  cubículos con relé de frecuencia tienen `StaSwitch`). La P de las 40 cargas
  EDAC monitoreadas nunca cae (`rms_edac_disparos.csv`).

**Implicación para Sienna**: el modelo PF *detecta* pero *no ejecuta* el EDAC
en RMS — el nadir de referencia 59.285 Hz es un nadir **sin deslastre**, no
"sin EDAC modelado". Para el estudio de sobredeslastre, la acción EDAC debe
construirse en PSID desde la tabla estática (`edac_detalle.csv`: etapa → carga
→ MW por escenario); la lista de los 13 relés que alcanzan a disparar ante la
pérdida de PC2 es la referencia de validación (con deslastre implementado en
Sienna, esas mismas etapas deben activarse, abriendo ≈1,158 MW del escalón 1
en P20 — de ahí la relevancia del estudio de sobredeslastre).

## Prioridad 3 — tablas de los DSL (oarray/FRT)

`data/raw/salida_oarray_20260717_231716/dsl_tablas.csv` (script
`scripts/pf/oarray_vm.py`): **79 tablas recuperadas, 1,959 valores** en formato
largo (dsl_ruta, model_name, tabla, fila, columna, valor). Incluye lo que
faltaba de los parques eólicos:

- `Grid Protection Model`: TuunderuWT/TuoveruWT (48+24 valores — curvas de
  ride-through de tensión) y TfunderfWT/TfoverfWT (protección de frecuencia)
- `Current limitation model`: ipmaxuWT/iqmaxuWT (límites de corriente vs U)
- `P control model type 3` (wp) y `QP and QU limitation model` (qmaxpp/qmaxuu/…)
- Governor MAN (barcazas): Itable/Ptable/SmP/SmI/SmD/NRGME

**Pendiente**: los parámetros `array_LVRT/array_HVRT/array_PFP/array_QU` de las
plantas **solares** (Monte Plata Solar, PF Martí, Maranatha, …) siguen ilegibles
por API (200 warnings — mismos objetos que fallaron en el export previo);
probablemente haya que leerlos a mano desde la GUI si la Fase 5 los necesita.

## Costos de arranque (Prioridad 3b)

El workbook MODOM (`MODOM_DIARIO_*.xlsm`) **no está en esta VM** — solo existe
en la PC principal. No se pudo extraer la hoja de arranques desde aquí.
