# data/raw — Datos confidenciales (NO se versionan)

Copiar aquí desde la copia local de `modom-pypsa`:

1. **Export PowerFactory** — la carpeta completa más reciente:
   ```
   modom-pypsa/data/external/salida_PDD_30_09_2025_*/   →   data/raw/salida_PDD_30_09_2025_*/
   ```
   (incluye barras.csv, lineas.csv, transformadores2/3.csv, cargas.csv,
   generadores_sinc.csv, generadores_est.csv, shunts.csv, svc.csv, tipos_*.csv,
   resumen.csv y todos_los_elementos/ElmDsl.csv)

2. **Tablas canónicas MODOM**:
   ```
   modom-pypsa/data/processed/   →   data/raw/processed/
   ```
   (buses, generadores con costos/rampas/tiempos mínimos, ramas, cargas,
   snapshots, flowgates e_fgate, factores nodales VEROPE)

3. **Coordenadas** (opcional, para mapas):
   ```
   modom-pypsa/data/external/buses_with_coords.csv   →   data/raw/
   ```

4. **Workbook MODOM crudo** (opcional, fuente original de la capa canónica):
   ```
   MODOM_DIARIO_dd-mm-yyyy_V449.xlsm
   ```
   La Fase 1 lee las tablas ya procesadas de `processed/`; el workbook queda
   como respaldo para regenerarlas con los scripts de modom-pypsa.

Todo lo que esté en esta carpeta (excepto este README) está excluido por `.gitignore`.

Estado actual: `salida_PDD_30_09_2025/`, `processed/`, `buses_with_coords.csv`
y el workbook MODOM ya están copiados.

---

## Excepción 2026-07-17 — extracción hecha en la VM (transferencia vía repo)

Por decisión del dueño del repo, las tres carpetas de la sesión de extracción
en la VM con DIgSILENT **sí se commitearon** (añadidas con `git add -f`) para
sacarlas de la VM. Son:

| Carpeta | Contenido | Lo usa |
|---|---|---|
| `salida_bloqueI_edac_20260717_111009/` | **Bloque I**: `escenario_P20_{cargas,generacion,taps}.csv`, `comldf_opciones.json` + **EDAC**: `edac_detalle.csv`, `edac_aguas_abajo.csv`, `edac_mw_por_escenario.csv` (P01–P24), `escenarios_demanda.csv` | Fase 2 (cerrar meta 0.005 pu) y v2 dinámica (sobredeslastre) |
| `salida_rms_edac_20260717_113111/` | RMS pérdida PC2 con protecciones activas: `rms_edac_series.csv` (f barras, speeds, P cargas EDAC), `rms_edac_disparos_reles.csv` (13 relés etapa 1 a t≈3.2 s), `rms_edac_output.txt` | Fase 5 / validación EDAC en PSID |
| `salida_oarray_20260717_231716/` | `dsl_tablas.csv`: 79 tablas IntMat (FRT eólicos, límites de corriente, governor MAN) | Fase 5 (afinar WECC genéricos) |

**En la PC principal**: un `git pull` deja las carpetas ya en su lugar
(`data/raw/`). Hallazgos y guía de lectura: `validation/extraccion_vm_20260717.md`.

**Después de transferir** (opcional, recomendado): sacarlas del versionado para
volver a la regla general — `git rm -r --cached data/raw/salida_bloqueI_edac_20260717_111009 data/raw/salida_rms_edac_20260717_113111 data/raw/salida_oarray_20260717_231716`
y commitear; los archivos quedan en disco. (Nota: seguirán en el historial de
git salvo reescritura del historial.)
