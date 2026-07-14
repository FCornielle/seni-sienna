# Plan: Recreación del SENI (República Dominicana) en Sienna (NREL)

**Fecha:** 14 de julio de 2026
**Autor:** Fernando Cornielle (con asistencia de Claude)
**Estado:** Plan aprobado — Fase 0 pendiente de iniciar

---

## 1. Contexto y objetivo

Existen actualmente dos proyectos que modelan el Sistema Eléctrico Nacional Interconectado (SENI) de la República Dominicana:

1. **[Feasibility-Study](https://github.com/FCornielle/Feasibility-Study)** — Plataforma interactiva de estudios de interconexión PV+BESS sobre el modelo PowerFactory del SENI (proyecto "PDD 30-09-2025", 24 escenarios horarios P01–P24). Automatiza vía la API Python de PowerFactory 2024:
   - Flujo de carga y balance del sistema
   - Contingencias N-1
   - Cortocircuito (aporte de la planta vs capacidad de ruptura)
   - Estabilidad de pequeña señal (eigenvalores, amortiguamiento vía matrix-pencil)
   - Estabilidad transitoria, de tensión (curvas P-V) y de frecuencia (RMS)
   - Cuasi-dinámico 24h con datos reales del Organismo Coordinador (OC)
   - Informe de interconexión consolidado (formato "Estudio de Acceso al SENI – PE Sajoma")

   Criterios de aceptación del **Código de Conexión (Ley 125-01)**: tensión ±5% (0.95–1.05 pu en 69/138/345 kV), N-1 sin sobrecargas nuevas, nadir de frecuencia ≥ 59.2 Hz (primer escalón EDAC), sin reducción de amortiguamiento de modos electromecánicos. Veredicto por deltas: solo se señalan violaciones "introducidas o empeoradas" respecto al caso base.

2. **[modom-pypsa](https://github.com/FCornielle/modom-pypsa)** — Réplica auditable del despacho diario del OC (MODOM, MILP en GAMS) usando PyPSA + pandapower, en 4 capas:
   - **Capa 1**: datos canónicos MODOM (717 barras; buses, generadores, ramas, cargas, snapshots; mapeo por `for_name`)
   - **Capa 2a**: despacho DC LP con commitment fijo (R²≈0.94 vs MODOM), factores nodales de demanda, flowgates N-1 como restricciones duras (fg1 ≤ 200 MW, fg2 ≤ 670 MW)
   - **Capa 2b**: MILP completo (commitment binario, arranques, rampas, tiempos mínimos, reservas RPF/RSF) resuelto en ~30 s con HiGHS
   - **Capa 3**: verificación AC con pandapower sobre el export DIgSILENT (tensiones y cargabilidad, 24 horas convergen)
   - **Capa 4**: lazo iterativo DC↔AC de factores de pérdidas nodales hasta convergencia

**Objetivo de este plan**: recrear todo lo recreable en **Sienna**, la plataforma open-source (BSD-3, Julia) de modelado de sistemas de potencia de NREL, unificando en una sola plataforma lo que hoy requiere PowerFactory (propietario) + PyPSA + pandapower, y evaluando honestamente qué NO se puede migrar.

**Ventaja clave**: los datos ya existen. El repo modom-pypsa contiene exportaciones CSV completas del modelo PowerFactory (`data/external/salida_PDD_*/`) y las tablas canónicas MODOM procesadas. No hay que levantar el sistema desde cero.

---

## 2. Qué es Sienna y qué paquete cubre cada necesidad

Sienna ([sienna-platform.github.io/Sienna](https://sienna-platform.github.io/Sienna/), [github.com/Sienna-Platform](https://github.com/Sienna-Platform)) se organiza en tres dominios de aplicación:

| Dominio | Paquete | Qué cubre del SENI |
|---|---|---|
| **Sienna\Data** | [PowerSystems.jl](https://github.com/Sienna-Platform/PowerSystems.jl) (PSY) | El `System`: 717 barras, líneas, trafos, generadores, cargas, series temporales de demanda/renovables, reservas como servicios, `TransmissionInterface` (flowgates) |
| Sienna\Data | [PowerFlows.jl](https://github.com/Sienna-Platform/PowerFlows.jl) | Flujo de carga AC (Newton-Raphson) y DC — reemplaza la capa pandapower |
| Sienna\Data | [PowerNetworkMatrices.jl](https://github.com/Sienna-Platform/PowerNetworkMatrices.jl) | Matrices PTDF, LODF, Ybus → contingencias N-1, flowgates |
| **Sienna\Ops** | [PowerSimulations.jl](https://github.com/Sienna-Platform/PowerSimulations.jl) (PSI) | UC MILP + despacho económico (reemplaza MODOM/PyPSA): commitment, arranques, rampas, min up/down, **reservas co-optimizadas nativas**, redes CopperPlate/PTDF/DC, simulaciones secuenciales día-adelante→tiempo-real con feedforwards |
| Sienna\Ops | [StorageSystemsSimulations.jl](https://github.com/Sienna-Platform/StorageSystemsSimulations.jl) | BESS (los estudios PV+BESS del Feasibility-Study) |
| Sienna\Ops | [HydroPowerSimulations.jl](https://github.com/Sienna-Platform/HydroPowerSimulations.jl) | Hidroeléctricas del SENI (embalses, filo de agua) |
| **Sienna\Dyn** | [PowerSimulationsDynamics.jl](https://github.com/Sienna-Platform/PowerSimulationsDynamics.jl) (PSID) | Pequeña señal (eigenvalores/amortiguamiento) y simulaciones transitorias RMS/EMT-fasorial; diseñado para integración de recursos basados en inversores |
| Utilidades | [PowerGraphics.jl](https://github.com/Sienna-Platform/PowerGraphics.jl) / [PowerAnalytics.jl](https://github.com/Sienna-Platform/PowerAnalytics.jl) | Gráficas y analítica de resultados de simulación |
| Utilidades | [PowerSystemCaseBuilder.jl](https://github.com/Sienna-Platform/PowerSystemCaseBuilder.jl) | Casos de prueba para validar el entorno y aprender |
| Base | [InfrastructureSystems.jl](https://github.com/Sienna-Platform/InfrastructureSystems.jl) | Infraestructura de series temporales y serialización (interno) |

---

## 3. Inventario de datos disponibles

### De modom-pypsa (`data/external/salida_PDD_*/` — export completo de PowerFactory)

| Archivo | Contenido | Destino en PSY |
|---|---|---|
| `barras.csv` | Barras/nodos (tensión base, zona) | `ACBus` |
| `lineas.csv` + `tipos_lineas.csv` | Líneas de transmisión (R, X, B, límites) | `Line` |
| `transformadores2.csv` + tipos | Trafos 2 devanados (impedancia, taps) | `Transformer2W` / `TapTransformer` |
| `transformadores3.csv` | Trafos 3 devanados | Equivalente estrella: 3×2W + barra ficticia |
| `cargas.csv` + `tipos_cargas.csv` | Cargas | `PowerLoad` |
| `generadores_sinc.csv` + `tipos_generadores.csv` | Generadores síncronos | `ThermalStandard` / `HydroDispatch` |
| `generadores_est.csv` | Generadores estáticos (PV, eólica, BESS) | `RenewableDispatch` / `EnergyReservoirStorage` |
| `shunts.csv`, `svc.csv` | Compensación shunt y SVC | `FixedAdmittance` / fuente reactiva |
| `motores_asinc.csv` | Motores asíncronos | Carga equivalente (estático) / modelo dinámico (PSID) |
| `todos_los_elementos/ElmDsl.csv` | Modelos de control dinámico (DSL) | Insumo para mapeo a modelos PSID |
| `resumen.csv` | Estadísticas del modelo | Validación de conteos |

Además: `buses_with_coords.csv` (coordenadas), tablas canónicas MODOM en `data/processed/` (costos CVP, rampas, tiempos mínimos, commitment, disponibilidad, demanda con factores nodales VEROPE, flowgates `e_fgate`), y datos horarios reales del OC.

### De Feasibility-Study
- Definición metodológica de los 6 estudios y sus criterios de aceptación (Código de Conexión)
- Coordenadas de subestaciones, integración API OC
- Lógica de veredicto por deltas (reutilizable como especificación)

> ⚠️ **Confidencialidad**: los exports de PowerFactory y datos del OC no están en GitHub; están localmente en esta PC. Se copiarán a `data/raw/` (excluida de git).

---

## 4. Matriz de cobertura: ¿qué se puede recrear en Sienna?

| # | Estudio / capacidad | Herramienta actual | En Sienna | Viabilidad |
|---|---|---|---|---|
| 1 | Despacho horario mínimo costo (LP, commitment fijo) | PyPSA | PSI `EconomicDispatch` + red PTDF | ✅ Directa |
| 2 | UC MILP (arranques, rampas, min up/down) | PyPSA MILP | PSI `UnitCommitment` + HiGHS | ✅ Directa, formulación más rica |
| 3 | Reservas RPF/RSF co-optimizadas | **Pendiente** en modom-pypsa | PSY `VariableReserve{ReserveUp/Down}` + PSI | ✅ **Mejora**: Sienna lo trae nativo |
| 4 | Flowgates N-1 (límites duros fg1/fg2) | Restricciones custom | PSY `TransmissionInterface` | ✅ Directa |
| 5 | Factores nodales / lazo pérdidas DC↔AC | Scripts custom | PSI + PowerFlows en lazo (script Julia) | ✅ script propio (patrón ya probado) |
| 6 | Flujo de carga AC (verificación 0.95–1.05 pu) | pandapower | PowerFlows.jl | ✅ Directa |
| 7 | Contingencias N-1 estáticas | PowerFactory | LODF (PowerNetworkMatrices) + AC post-contingencia | ✅ Directa |
| 8 | Cuasi-dinámico 24h | PowerFactory QDS | Secuencia de flujos AC con series horarias | ✅ script propio |
| 9 | Curvas P-V (estabilidad de tensión) | PowerFactory | Barrido de carga con PowerFlows | ✅ script propio |
| 10 | Pequeña señal (eigenvalores, damping) | PowerFactory | PSID `small_signal_analysis` | ✅ requiere capa dinámica (ver #12) |
| 11 | Estabilidad transitoria RMS (fallas, disparos) | PowerFactory | PSID `Simulation` + perturbaciones | ✅ requiere capa dinámica |
| 12 | Modelos dinámicos máquinas/inversores | DSL PowerFactory | Biblioteca PSID: GENROU/GENSAL/Marconato, AVRs (SEXS, EXST1, ESAC…), governors (TGOV1, GAST, HYGOV), PSS (IEEEST), renovables WECC genéricos (REGCA + REECB + REPCA), grid-forming (droop, VSM) | ⚠️ **Mapeo manual DSL→PSID: el mayor esfuerzo técnico del proyecto** |
| 13 | Respuesta de frecuencia (nadir vs 59.2 Hz, EDAC) | PowerFactory | PSID: pérdida de generación + deslastre por pasos modelado custom | ⚠️ EDAC se modela custom (callbacks/perturbaciones) |
| 14 | Cortocircuito IEC 60909 | PowerFactory | **No existe en Sienna** | ❌ **Gap** — mantener pandapower `calc_sc` o PowerFactory |
| 15 | Protecciones / relés | PowerFactory | No soportado | ❌ Fuera de alcance |
| 16 | Plataforma web / mapa interactivo | Next.js + FastAPI | Fuera de Sienna; resultados (Arrow/CSV/JSON) se integran a las webs existentes | ⚠️ opcional, fase posterior |

**Conclusión**: ~85% del alcance funcional es recreable en Sienna, con mejoras netas en despacho (reservas co-optimizadas, simulaciones secuenciales DA→RT que PyPSA no ofrece out-of-the-box). Los gaps reales son cortocircuito IEC 60909 y protecciones — se mantiene la herramienta actual solo para eso. El esfuerzo dominante es (a) el traductor PowerFactory→PSY y (b) el mapeo de modelos dinámicos DSL→PSID.

---

## 5. Arquitectura del proyecto

```
37 - SENI- SIENNA/
├── PLAN_SENI_SIENNA.md          # este documento
├── Project.toml                 # entorno Julia (PSY, PSI, PSID, PowerFlows, HiGHS…)
├── .gitignore                   # excluye data/raw (confidencial) y resultados pesados
├── data/
│   ├── raw/                     # ← copiar aquí: salida_PDD_*/ y tablas MODOM (NO va a git)
│   └── sys/                     # System serializado (to_json) por escenario
├── src/
│   ├── SeniSienna.jl            # módulo principal
│   ├── parse_powerfactory.jl    # CSVs PF → structs PSY
│   ├── parse_modom.jl           # costos, rampas, commitment, reservas, flowgates → PSY
│   ├── timeseries.jl            # demanda nodal, perfiles solar/eólico, snapshots 24/48h
│   ├── build_system.jl          # ensambla y valida el System completo
│   └── dynamics_library.jl      # mapeo DSL PowerFactory → modelos PSID
├── scripts/
│   ├── 01_build_system.jl       # Fase 1
│   ├── 02_powerflow_validation.jl  # Fase 2
│   ├── 03_dispatch_ed.jl        # Fase 3 (≙ Layer 2a de modom-pypsa)
│   ├── 04_uc_milp.jl            # Fase 3 (≙ Layer 2b + reservas)
│   ├── 05_contingency_n1.jl     # Fase 4
│   ├── 06_quasi_dynamic_24h.jl  # Fase 4
│   ├── 07_small_signal.jl       # Fase 5
│   └── 08_transient_frequency.jl # Fase 5
├── validation/                  # comparativas vs PowerFactory / modom-pypsa / MODOM real
└── test/                        # tests del traductor (conteos, balances, impedancias)
```

---

## 6. Fases de implementación

### Fase 0 — Entorno y datos *(prerequisito, ~1 sesión)*
1. Instalar Julia ≥ 1.10 (vía `juliaup` en Windows).
2. `Pkg.instantiate()` del `Project.toml` (PSY, PSI, PSID, PowerFlows, PowerNetworkMatrices, StorageSystemsSimulations, HydroPowerSimulations, PowerSystemCaseBuilder, HiGHS, DataFrames, CSV).
3. Verificar el entorno construyendo un caso de `PowerSystemCaseBuilder.jl` (p. ej. RTS-GMLC) y corriendo un UC de prueba.
4. Copiar los datos locales a `data/raw/`: carpeta(s) `salida_PDD_*` completas y `modom-pypsa/data/processed/`.

### Fase 1 — Sienna\Data: construir el `System` del SENI *(el corazón del proyecto)*
- Implementar `parse_powerfactory.jl`: lectura de los CSVs y creación de componentes PSY (tabla de mapeo de la sección 3). Cuidados: conversión de impedancias a pu en la base del sistema (100 MVA), taps de trafos, trafos 3W → estrella equivalente, signos de shunts.
- Implementar `parse_modom.jl`: enriquecer generadores con datos operativos MODOM vía **mapeo por `for_name`** (mismo patrón que modom-pypsa usa para inyectar en pandapower — ya probado): curvas de costo (CVP declarado), rampas, min up/down, costos de arranque, disponibilidad, commitment.
- Implementar `timeseries.jl`: demanda por barra (factores nodales VEROPE) y perfiles solar/eólico como `SingleTimeSeries` (24/48 snapshots); versión `Deterministic` para simulaciones secuenciales.
- Reservas RPF/RSF como `VariableReserve{ReserveUp}` / `{ReserveDown}` con sus requisitos horarios; flowgates como `TransmissionInterface` sobre los grupos de líneas de `e_fgate`.
- Serializar con `to_json(sys, "data/sys/seni_<escenario>.json")`.
- **Validación**: conteos de componentes vs `resumen.csv`; capacidad total por tecnología vs capa canónica MODOM; tests en `test/`.

### Fase 2 — Flujo de carga: validar la red traducida
- AC power flow (PowerFlows.jl) sobre el snapshot base.
- Comparar tensión (módulo y ángulo) y flujos barra a barra contra PowerFactory o contra los resultados pandapower de modom-pypsa.
- **Criterio de aceptación: |ΔV| < 0.005 pu en barras ≥ 69 kV.** No avanzar a Fase 3 sin cerrar esto — valida impedancias, taps y topología.

### Fase 3 — Sienna\Ops: despacho y UC (réplica y superación de modom-pypsa)
- `03_dispatch_ed.jl`: `DecisionModel` de despacho económico con commitment fijo de MODOM (`ThermalBasicDispatch` + parámetro de estado), red `PTDFPowerModel`, flowgates activos. **Meta: R² ≥ 0.94 vs despacho MODOM real** y coincidencia con los resultados PyPSA (misma formulación → mismos resultados).
- `04_uc_milp.jl`: UC completo (`ThermalStandardUnitCommitment`) con reservas RPF/RSF co-optimizadas — **cierra el pendiente de modom-pypsa**. BESS con `StorageDispatchWithReserves`; hidro con HydroPowerSimulations.
- Opcional (mejora única de Sienna): `Simulation` secuencial día-adelante (UC 24–48h) → despacho horario con feedforward de commitment — el flujo real del OC (PDD → redespacho).
- Lazo DC↔AC de pérdidas: portar la lógica de `loss_factors.py` como script Julia: PSI despacha → PowerFlows AC → re-estimar factores nodales → re-despachar hasta convergencia.

### Fase 4 — Contingencias N-1 y cuasi-dinámico
- `05_contingency_n1.jl`: screening con LODF sobre todas las ramas; AC post-contingencia (PowerFlows) en las críticas; veredicto según Código de Conexión (sin sobrecargas nuevas, tensiones en banda) con la lógica de deltas del Feasibility-Study.
- `06_quasi_dynamic_24h.jl`: bucle de 24 flujos AC con las series horarias (demanda OC + despacho de Fase 3) ≙ estudio QDS. Salidas: perfiles horarios de tensión y cargabilidad.

### Fase 5 — Sienna\Dyn: pequeña señal y transitorios *(mayor esfuerzo e incertidumbre)*
- `dynamics_library.jl`: mapear cada generador a `DynamicGenerator` PSID (máquina + shaft + AVR + governor + PSS) y cada inversor a `DynamicInverter` (modelos genéricos WECC: REGCA + REECB + REPCA; grid-forming si aplica). Fuentes: `ElmDsl.csv` y `tipos_generadores.csv` del export; donde falten parámetros, usar valores típicos por tecnología **documentando cada supuesto** en la propia librería.
- Estrategia incremental: empezar con las 10–20 máquinas más grandes (Punta Catalina, AES Andrés, EGE Haina, Quisqueya, hidros principales…) con el resto agregado/estático, y refinar por etapas.
- `07_small_signal.jl`: `small_signal_analysis` — eigenvalores, frecuencias y amortiguamiento de modos electromecánicos; comparar contra el estudio de pequeña señal de PowerFactory.
- `08_transient_frequency.jl`: falla trifásica + despeje (CCT), pérdida del mayor generador → nadir vs 59.2 Hz con EDAC modelado como deslastre por pasos (perturbaciones `LoadChange` condicionadas), hueco de tensión en el punto de interconexión de una planta PV+BESS.

### Fase 6 — Análisis, reportes y cierre de gaps
- PowerAnalytics + PowerGraphics: curvas de despacho por tecnología, precios nodales (duales), heatmap de commitment — paridad con la web de modom-pypsa.
- Cortocircuito: flujo híbrido documentado — exportar el `System` a pandapower (o usar PowerFactory) solo para `calc_sc` IEC 60909.
- Funciones de veredicto reutilizables estilo Feasibility-Study ("introduce o empeora") para tensión, sobrecargas, damping y nadir.
- (Opcional) API de resultados para integrarlos a las plataformas web existentes.

---

## 7. Riesgos y consideraciones

| Riesgo | Mitigación |
|---|---|
| Trafos de 3 devanados sin soporte nativo maduro en PSY | Equivalente estrella (3×2W + barra ficticia); validar en Fase 2 |
| Modelos DSL propietarios sin equivalente PSID directo | PSID permite modelos custom en Julia; priorizar modelos estándar IEEE/WECC; documentar supuestos |
| Datos confidenciales (modelo PF, API OC) | `data/raw/` fuera de git; nunca publicar el System serializado con datos reales |
| Curva de aprendizaje de Julia/Sienna | Tutoriales oficiales (SiennaOpsTutorial, docs de cada paquete); estructura por scripts numerados; validar contra resultados conocidos en cada fase |
| Diferencias de convergencia AC (PowerFlows vs pandapower vs PF) | Fase 2 como compuerta de calidad; tolerancias explícitas |
| Escala (717 barras, MILP horario) | Holgada para Sienna (NREL corre sistemas de decenas de miles de barras); HiGHS ya resuelve el MILP del SENI en ~30 s en PyPSA |
| Cortocircuito y protecciones | Fuera del alcance de Sienna — mantener herramienta actual solo para esto |

---

## 8. Criterios de verificación end-to-end

| Fase | Verificación | Criterio |
|---|---|---|
| 1 | Conteos y balances del System vs `resumen.csv` y capa canónica | 100% de coincidencia |
| 2 | Flujo AC vs PowerFactory/pandapower | \|ΔV\| < 0.005 pu (≥ 69 kV) |
| 3 | Despacho por unidad y costo total vs MODOM real y vs PyPSA | R² ≥ 0.94; desviación de costo < 1% vs PyPSA |
| 4 | Lista de contingencias críticas vs PowerFactory | Mismas contingencias señaladas |
| 5 | Modos electromecánicos (f, ζ) vs pequeña señal PF; nadir de frecuencia | Modos dominantes comparables; nadir coherente con estudios PF |
| — | Tests Julia del traductor | `] test` en verde |

---

## 9. Referencias

- Sienna: https://sienna-platform.github.io/Sienna/ · https://github.com/Sienna-Platform
- Documentación: PowerSystems.jl, PowerSimulations.jl, PowerSimulationsDynamics.jl (docs en cada repo)
- Proyectos propios: [Feasibility-Study](https://github.com/FCornielle/Feasibility-Study) · [modom-pypsa](https://github.com/FCornielle/modom-pypsa)
- Marco regulatorio: Código de Conexión del SENI (Ley 125-01); "Programación de la Operación de Corto Plazo" (OC)
