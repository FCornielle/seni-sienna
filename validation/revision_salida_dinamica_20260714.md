# Revisión de la extracción dinámica `salida_dinamica_20260714_203429`

**Veredicto: APTA para la Fase 5.** Los 8 bloques de la especificación están completos,
con 3 observaciones menores (abajo). Proyecto PDD 30-09-2025, escenario **P20**,
extraída 2026-07-14 en modo solo lectura (sandbox `SBX_H_20260714_203437`).

## Completitud vs especificación

| Bloque | Archivo | Filas | Estado |
|---|---|---|---|
| A Frames/slots | `frames_slots.csv` | 1,123 (700 ElmSym + 423 ElmGenstat; **129 máquinas únicas**) | ✅ |
| B Parámetros DSL | `dsl_parametros.csv` | **14,134** pares parámetro→valor | ✅ |
| C Complemento síncronos | `sym_extra.csv` | 81 tipos, con `tqs0` ✓ | ✅ |
| D Inversores | `genstat_dinamica.csv` | 49 | ✅ |
| E Control de estación | `stactrl.csv` | 15 (incl. nodo piloto 345 kV → Punta Catalina 1/2) | ✅ |
| F EDAC | `edac_etapas.csv` | 1,668 etapas; **134 activas** (etapa y relé en servicio) | ✅ |
| G SVC | `svc_dinamica.csv` | 2 | ✅ |
| H Referencias | loadflow 4,835 barras; modal 1,380 modos; RMS 3,295 pasos | | ✅ |

## Referencias para validar Sienna (Bloque H)

- **RMS**: pérdida de **Punta Catalina 2 (360 MW)** → **nadir COI = 59.285 Hz** (COI de 71 máquinas).
  Ojo: queda por debajo del primer escalón EDAC del modelo (59.30 Hz) pero esa etapa
  aparece fuera de servicio — revisar en Fase 5 qué etapas activas cruzaría.
- **Pequeña señal**: 1,380 modos; **26 modos oscilatorios electromecánicos (0.1–3 Hz) con ζ < 10%**
  → conjunto objetivo de comparación PF vs PSID.
- `modal_bypass_dsl: 10` — 10 DSL fueron puenteados por el análisis modal de PF (listados en `_WARNINGS.txt`).

## Inventario de modelos de control encontrados (→ mapeo PSID, Fase 5)

| Familia | Modelos (uso) | Equivalente PSID |
|---|---|---|
| Governors | `gov_GGOV1`, `gov_HYGOV`, `gov_DEGOV1`, `pcu_GAST2A`, `pmu_TrWHydroFrancis`, `NEYPRIC 1500` | GeneralGovModel (GGOV1), HydroTurbineGov (HYGOV), DEGOV1; GAST2A/NEYPRIC → aproximar o custom |
| AVR | `vco_EXAC1`, `vco_EXAC1A`, `vco_IEEET1`, `avr_ESAC5A`, `avr_ESAC8B`, `vco_Unitrol F` | EXAC1, IEEET1 nativos; ESAC5A/ESAC8B/Unitrol → mapear a familia AC/ST o custom |
| PSS | `pss_PSS2A`, `pss_PSS2B`, variante IEEE 2A/2B/2C | IEEE PSS2A/2B en PSID |
| Eólica | `WD3ModuleControl` (tipo 3/DFIG), `Protection`, `Current limitation`, `P control type 3` | WECC genéricos (REGC+REEC+REPC) como aproximación |
| Solar | `CONTROL_SYSTEM`, `ELEC_CTRL`, `ReactPow_Control`, `Current_Control`, `PVarray` | WECC genéricos PV |

## Observaciones (no bloqueantes)

1. **Tablas `oarray_*` no legibles** (~90 warnings): lookup tables de protección/límites de
   parques eólicos (Guanillo, Los Guzmancito, …). Impacto: curvas FRT detalladas; la Fase 5
   arranca con los genéricos WECC, se pueden pedir después si hace falta afinar.
2. **`sg10`/`sg12` = 0 y `dpu` = 0** en todos los tipos: el modelo PF no carga saturación
   ni amortiguamiento mecánico → PSID sin saturación (consistente, no es pérdida).
3. **4 DSL sin `sParams`** (`PVarray`, `FILTER_MEAS`, bloques trigonométricos): auxiliares
   de plantas PV, sin parámetros que extraer. OK.

## Ubicación

`data/raw/salida_dinamica_20260714/salida_dinamica_20260714_203429/` (no versionada; zip original en `data/raw/`).
