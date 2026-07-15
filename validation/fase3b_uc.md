# Fase 3b — UC MILP con PowerSimulations vs MODOM

**Estado: COMPLETA — el UC binario con reservas co-optimizadas corre de punta a
punta en PSI** ([scripts/04_uc_milp.jl](../scripts/04_uc_milp.jl)). Cierra el
pendiente de reservas de modom-pypsa.

## Formulación (PowerSimulations 0.30)

- `ThermalStandardUnitCommitment`: commitment binario, arranque/parada, rampas
  (RS/RB), tiempos mínimos (TMO/TMPA), estado inicial (YN)
- `HydroDispatchRunOfRiver` (techo = disponibilidad horaria), `RenewableFullDispatch`
- Red tipo MODOM: `PTDFPowerModel` + `StaticBranchUnbounded` (sin límites por
  rama) + `TransmissionInterface`/`ConstantMaxInterfaceFlow` (flowgates)
- **Reservas RPF y RSF**: `VariableReserve{ReserveUp}` + `RangeReserve`, requisito
  horario = 3% de la demanda (RRPF/RRSF de model_options), contribuyentes con
  MRPF/MRSF > 0
- System podado a la isla principal (`prune_to_main_island!`, PTDF requiere red
  conexa) y series transformadas a Deterministic (`transform_single_time_series!`)
- HiGHS, gap 0.1%, resuelve en segundos

## Resultados vs MODOM (1,872 pares unidad-hora)

| Métrica | Valor |
|---|---|
| Coincidencia de commitment on/off | **89.9 %** |
| R² de despacho | 0.724 |
| Costo variable Sienna / MODOM | 159.5 / 263.5 M$ (−39%) |
| Reserva RPF y RSF asignadas | 94.3 MW/h cada una (requisito cumplido) |

Detalle: `fase3b_uc_comparison.csv`.

## Lectura de los resultados

El UC libre **comete menos unidades y más baratas** que MODOM. Es el comportamiento
esperado, no un error de implementación:

1. **Sin costos de arranque** (la capa canónica no trae $/arranque identificable;
   con costo 0 el MILP enciende/apaga sin penalización) → sobre-optimiza
2. MODOM asegura unidades por criterios que este MILP no ve: tensión/estabilidad
   por zona, AGC, límites de arranques (NAMX), mantenimientos y pruebas
3. El despacho fijado por MODOM (Fase 3a) es la comparación de *despacho*
   (R² 0.957 ✓); la 3b compara *decisiones de commitment* — su valor está en que
   el MILP completo funciona y sirve de base para Scenario Studio en Sienna

## Mejoras identificadas (backlog)

- Costos de arranque: extraer del workbook MODOM (`MODOM_DIARIO_V449.xlsm`) la
  hoja/columna de arranques y mapearla (TCG/HOC por confirmar con la transcripción)
- Disponibilidad horaria térmica (`generator_availability`) como derating
- Hidro como contribuyente de reservas: bloqueado por bug de orden de construcción
  en HydroPowerSimulations 0.11 + PSI 0.30 (`HydroServedReserveUpExpression`
  busca la variable del servicio antes de su creación) — reportable upstream
- `must_run` para unidades que MODOM nunca apaga (Punta Catalina, AES Andrés)
  reduciría la brecha de commitment
