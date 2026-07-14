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
