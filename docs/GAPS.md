# Gaps de implementación — plan de cierre

Clasificación por lo que se necesita para cerrarlos. **Tipo A en curso**; B/C/D
almacenados aquí para abordarlos después de cerrar A.

## A — Cierro yo solo (solo tiempo, sin datos externos)  ← EN CURSO
| Gap | Qué hago | Estado |
|---|---|---|
| must-run en el UC | Unidades siempre ON en MODOM → `must_run=true` | ✅ commitment 89.9→**93.9%**, R² 0.72→**0.93** |
| Lazo de pérdidas DC (eq. 29-30) | pérdidas P=r·f² por rama, 50/50 a barras, re-solve caliente | ✅ costo −16%→**−2.8%**, R² 0.957→**0.971** |
| v2 dinámica: inversores WECC | `DynamicInverter` REGCA1+REECB1+REPCA1 grid-following en las 13 renovables (`attach_dynamic_models!(...; inverters=true)`) | ✅ **RMS inicializa** (Simulation ResidualModel con 13 inversores). Pequeña señal con inversores topa un bug interno de PSID (`UndefVarError i`, `jacobian.jl:216`) → estudios modales quedan en su baseline sin inversores. Aporte nocturno ≈0 (solar 0); útil en escenario diurno |
| v2 dinámica: GGOV1 real | Modelo custom en Julia (PSID 0.15 no inicializa GeneralGovModel) | pendiente (esfuerzo focalizado) |
| NAMX (nº máx arranques) | Σ start ≤ NAMX (restricción post-build en el JuMP de PSI) | ✅ verificado: las 3 unidades NAMX=1 (CESPM) son must_run (0 arranques) → satisfecho |
| Animación horaria del mapa | slider de hora en capa "vhora" (tensión por barra×hora del QDS) | ✅ 575 barras × 24 h |
| Empaquetado + selector P01–P24 | `create_app` (exe) y selector de escenario | pendiente (P01–P24 necesita datos → B) |

> **Nota de pérdidas**: el efectivo ~9% es algo mayor al físico (~5-6%) porque
> absorbe también el uplift OPLM de MODOM y el efecto de costo marginal; por eso
> el costo queda tan cerca (−2.8%). El loop nodal exacto (mapeo al System físico
> AC) sería el refinamiento fino.

### Por qué NO se pudieron cerrar "de golpe" los restantes
- **Embalses hidro (eq. 34-36)**: los datos locales (`hydro/reservoirs.csv`,
  `inflow.csv`) están en **hm³ de agua**, no en energía; convertir a MWh necesita
  η y salto por central (no verificables sin riesgo de física incorrecta) → de
  facto **tipo B** (falta el factor de conversión del OC).
- **Inversores WECC / GGOV1**: alto riesgo de inicialización en PSID 0.15 y
  **aporte ≈0 en el escenario nocturno** (solar 0 MW) → mal trade riesgo/valor.
  Requiere un escenario diurno + sesión focalizada.
- **create_app (exe)**: build lento y quisquilloso de PackageCompiler → sesión
  dedicada.

## B — Necesitan un DATO de la VM / OC (extracción)
Tras las Rondas 1–2 de extracción VM (`vm-extraccion-20260717`, `-2-20260804`) y
el código GAMS del MODOM (zip `MODOM DIARIO - 422`), el estado es:
- ~~**Embalses (RENDH, aportes, niveles)**~~ → ✅ **RESUELTO**: RENDH=1 (agua ya en
  MWh), presupuesto diario = DAT_NFIN (GAMS línea 743). Modelo en `scripts/03`
  (`HYDRO_BUDGET=1`).
- ~~**Costos de arranque C^ARR**~~ → ✅ **CONFIRMADO**: no es costo declarado, es
  CVP×PMN×TARR (ya en `build_modom_system.jl`).
- ~~**Shunts/SVC**~~ → ✅ **EXTRAÍDO y REFUTADO como causa** del residuo Este: solo
  2 capacitores (28 Mvar), 1 paso fijo, sin conmutar entre P01–P24. El residuo de
  Fase 2 es física del radial (PF ya en 0.90), no compensación. Ver `fase2_flujo_ac.md`.
- ~~**oarray_* FRT**~~ → ✅ **EXTRAÍDO** (`oarray_frt_completo.csv`, Ronda 2).
- ~~**Reserva Fría (RFA)**~~ → ✅ **MODELADA** (`scripts/04`). En el MODOM es un 4º
  estado (apagada en standby, `ACC+ARR+PAR+RFA=1`). Representada como reserva
  no-rodante: Σ Pmax·(1−on) de las 15 unidades RFA-elegibles del PSD ≥ requerimiento
  horario (diurno, 0→816 MW, respaldo solar). Restricción en 10 h; commitment 93.7%
  y R² 0.927 sin degradación (`reserva_fria_req.csv`, `reserva_fria_unidades.csv`).
- ~~**AGC como reserva separada**~~ → ✅ **RESUELTO**. La extracción de gobernadores
  (Ronda 2) confirmó que la secundaria del MODOM es **RSF-AGC combinada** (regulación
  + AGC automático = un producto 3%), no una reserva aparte: los 40 proveedores
  MRSF>0 que ya usaba el UC son AGC-capaces (mrsf ⊂ gobernador∪mrsf = 72). Se hizo
  explícita renombrando la reserva a **`RSF_AGC`** (build + scripts 04/14). UC:
  commitment 93.86%, R² 0.927 (baseline preservado), reserva media 94.3 MW.
- **Puntos de operación P01–P24**: integrados; script `16_validacion_p01_p24.jl`
  hecho. **Hallazgo honesto**: la validación económica por escenario NO sale limpia
  porque (a) la extracción no capturó el despacho renovable (`genstat P_desp=0` →
  Sienna cubre ~963 MW con térmico), (b) fecha distinta (canónico 11-06 vs PF
  30-09), (c) swap dual-fuel Gas↔Fuel-Oil. Síncrono Sienna +18.6% vs PF. **Uso
  correcto pendiente**: los P01–P24 son puntos de **flujo AC** → extender la Fase 2
  a los 24 escenarios, pero falta extraer las **tensiones de referencia** de los
  escenarios ≠ P20 (solo P20 tiene `tensiones_flujo.csv`). Tarea para la VM.

## C — Sienna NO puede (otra herramienta)
- **Cortocircuito IEC 60909**: mantener pandapower (`calc_sc`) / PowerFactory (flujo híbrido).
- **Coordinación de protecciones/relés**: fuera de alcance.

## D — Validación (necesitan referencia)
- **Comparación cuantitativa vs despacho real del OC** → ✅ **cerrado** vía la API
  del OC (`scripts/15_validacion_oc.jl`, pestaña "Validación OC"). Post-despacho
  real de la fecha del modelo (30-09-2025): energía total OC 81.4 vs Sienna 82.4
  GWh (+1.3%); térmica/solar/hidro dentro de ±10%. Diferencias explicadas:
  eólica (perfil canónico ≠ clima real del día) y fuel-oil vs gas (despacho
  dual-fuel). Extensible a más días cambiando el argumento de fecha.
- **Precios / CMG** → ✅ **cerrado** con la Lista de Mérito del PSD. `scripts/03`
  extrae el precio nodal (LMP = 10·dual del balance) → CMG horario (0 al mediodía
  solar, ~8700 RD$/MWh en la punta fuel-oil). El CVP del modelo correlaciona
  **Pearson 0.923** con el CVP definitivo del OC (ratio 1.10 por el desfase de
  precio de combustible jun→ago-2026). Pestaña "Precios" (`cmg_hora.csv`,
  `cvp_validacion.csv`, `psd_lista_merito.csv`).
- Match modo-por-modo de pequeña señal vs PowerFactory (más escenarios).
