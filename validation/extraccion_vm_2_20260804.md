# Extracción VM — Ronda 2 (2026-08-04)

**Entorno**: VM con PowerFactory 2024, proyecto "PDD 30-09-2025", escenario **P20**,
study case **BASE**, Python 3.9 + `powerfactory.pyd`.
**Script único**: `scripts/pf/extract_vm_r2.py` (`--solo shunts|op|agc|frt`).
Solo lectura: el flujo de carga corrió en un study case sandbox borrado al final y el
escenario quedó restaurado a P20. Responde a `EXTRACCION_VM_RONDA2.md`.

## Índice de salidas

| Carpeta en `data/raw/` | Archivos | Prioridad |
|---|---|---|
| `salida_shunts_svc_20260804_192856/` | `escenario_P20_shunts.csv`, `_svc.csv`, `_stactrl.csv`, `_qcap.csv`, `qcap_curvas.csv`, **`escenario_P20_tensiones_flujo.csv`** | P1 + P2 |
| `salida_op_P01_P24_20260804_191945/` | `op_cargas/op_generacion/op_taps/op_shunts_P01_P24.csv`, `resumen_por_escenario.csv` | P3 |
| `salida_agc_hidro_20260804_192058/` | `agc_participacion.csv`, `gov_parametros.csv`, `hidro_parametros.csv` | P4 + P5 |
| `salida_oarray_frt_20260804_192344/` | `oarray_frt_completo.csv`, `oarray_frt_resumen.csv` | P6 |

---

## P1 — Shunts, SVC y controladores de estación  ⭐

**30 shunts (25 en servicio), todos `shtype=2` (capacitores)**. Σ nominal en servicio
**448.0 Mvar**; Σ real en el flujo P20 **443.8 Mvar** (columna `Q_actual_Mvar`, signo PF
negativo = inyección capacitiva). Reparto: **69 kV → 405.5 Mvar**, 34.5 kV → 38.3 Mvar.
Los 5 fuera de servicio son Agua Clara, FALCONDO 1/2 y Matafongo 1/2 (todos 34.5 kV).

**El radial Este tiene mucho menos apoyo capacitivo del que sugería la hipótesis**: solo
**2 capacitores, 28.2 Mvar** en total — Higüey (`ZHIGUF-C1`, 17.0 Mvar nominales, 1 paso)
y La Romana Pueblo (`ZLRMAF-C1`, 15.6 Mvar, 1 paso). No hay capacitores en Bení, Chavón,
Guaymate ni Verón.

> ### ⚠️ Hallazgo que cambia el diagnóstico de la Fase 2
>
> **El propio PowerFactory resuelve el radial Este muy bajo.** Verificado leyendo `m:u`
> directamente del flujo (no inferido): **Higüey = 0.9017 pu**, y es el **mínimo absoluto
> de las 1,577 barras de 69 kV** del sistema (media 0.9912, máx 1.0479). La Romana Pueblo
> 0.9613, Guaymate 0.9620, La Romana 69 kV 0.9648, La Romana 138 kV 0.9579.
>
> Es decir: **no hay Mvar "perdidos" que recuperar en el Este** — el modelo de referencia
> ya está en 0.90 pu ahí. Si la Fase 2 da 0.04–0.055 pu *por debajo de PF* en esas barras,
> está llegando a ~0.85 pu y el problema no es la compensación capacitiva.
>
> Para poder comparar barra a barra se añadió **`escenario_P20_tensiones_flujo.csv`**:
> las **5,150 barras** con `V_pu`, ángulo, kV y una bandera `energizada` (4,668 lo están;
> las de V=0 son islas sin energizar y **no deben entrar en el error medio** — si la
> comparación de la Fase 2 las incluyó, ahí puede haber parte del sesgo).

**Todos los shunts son de 1 paso fijo**: `ncapa = ncapx = 1` y, según el barrido P01–P24
(`op_shunts_P01_P24.csv`), **el estado no cambia entre escenarios** (448.0 Mvar nominales
en los 24). O sea: pese a `iopt_asht=1` en el ComLdf, aquí no hay conmutación real de
escalones que reproducir — la diferencia entre PF y Sienna no viene por ahí.

**SVC**: los 2 de PVDC (34.5 kV), `qmin −10 / qmax +20 Mvar`, consigna 1.04 pu, cada uno
inyectando **20.5 Mvar** en P20 — es decir, **ambos por encima de su qmax nominal** (PF los
dejó pasarse ~0.5 Mvar; anotarlo si en Sienna se saturan a 20).

**Station controllers**: 15, todos en servicio, **14 con máquinas asignadas** (el de
"138 kV Nodo Piloto San Pedro de Macorís" tiene `n_maquinas = 0` y sin nudo piloto → es el
que sobra frente a los 14 que aplicó la Fase 2; **coincide, no falta ninguno**).
Consignas destacadas: Boca Chica 0.940, Bonao 3 0.974, Timbeque 2 0.979, Pimentel 0.980,
Itabo 0.988, Canabacoa 0.995, Valdesia 0.998, resto ≈1.00–1.015.

## P2 — Curvas de capacidad Q

`escenario_P20_qcap.csv`: 157 unidades (86 en servicio), con `Qmin_actual_Mvar` /
`Qmax_actual_Mvar` = **los límites que PF realmente usó** (atributos `cQ_min`/`cQ_max`,
en Mvar) además de `q_min`/`q_max` en pu de Sgn.

- **52 unidades referencian una curva `IntQlim`, pero solo 5 curvas tienen puntos
  legibles** (50 puntos en `qcap_curvas.csv`: GAMESA, LOPP2, Leistungsdiagramm,
  Q3QUISQ2, QUISQUEYA2). Las demás (p. ej. `Huawei_Capability_Curve`, `BESS CC`) existen
  como objeto pero con **todos los arrays vacíos** — PF cae de vuelta a `cQ_min/cQ_max`.
- `inputmod` indica las unidades de la curva: **0 = MW/Mvar**, **1 = pu de Sgn**.
- **Solo 4 unidades están contra su límite de Q** en P20 (Pimentel 2, Pimentel 3,
  Baiguaque 1, Aniana Vargas 2; Pimentel 3 incluso 0.3 Mvar por encima de `cQ_max`).

> **Conclusión para la Fase 2**: usar `Qmin_actual_Mvar`/`Qmax_actual_Mvar` por unidad
> (sustituyen a los límites planos del tipo) resuelve la hipótesis 2, pero **el efecto
> esperado es pequeño**: casi ninguna máquina está saturada en el punto P20.

## P3 — Puntos de operación P01–P24

Archivos largos con columna `escenario` (formato pedido): cargas (10,608 filas),
generación, taps y shunts. `resumen_por_escenario.csv` da el balance por escenario:

| | Demanda mín | Demanda máx |
|---|---|---|
| Escenario | **P08: 2,894.8 MW** | **P22: 3,655.2 MW** |

P20 = 3,624.3 MW de demanda / 3,625.5 MW de generación. Confirma lo de la Ronda 1: la
demanda 3,645 MW del export estático viejo corresponde a **P21/P23**, no a P20.

## P4 — AGC / control secundario

**Hallazgo: el modelo no tiene AGC.** No existe ningún `ElmSecctrl`, `ElmAgc` ni
`ElmFreqctrl` en el proyecto (verificado en `_META.json → inventario_clases_control`).
Los `ElmArea` (4) y `ElmZone` (11) son solo etiquetas geográficas, sin parámetros de
control. Los 15 `ElmStactrl` son control **de tensión**, no de frecuencia.

Por eso `agc_participacion.csv` reporta el **proxy de capacidad regulante primaria**, que
es lo que el modelo sí define, por máquina: área, `Pmin/Pmax`, `tiene_gobernador`,
`gov_modelo`, `estatismo_droop` (+ `droop_param`, el nombre real del parámetro leído) y
`margen_subida_MW = Pmax − P_desp`.

- 108 máquinas, **72 en servicio, 62 de ellas con gobernador**.
- **Margen de subida de las unidades gobernadas en servicio: 563.7 MW.**
- Estatismo legible en **49 unidades**; el nombre del parámetro varía por modelo
  (`Droop` en gov_DEGOV1 ≈ 0.056–0.060, `R` en GGOV1/TGOV1 = 0.05, `bp` en NEYPRIC…) —
  por eso se exporta `droop_param` junto al valor.
- Modelos: gov_GGOV1 (11), gov_DEGOV1 (10), gov_GAST (5), pcu_GAST2A (5), gov_HYGOV (4)…
- `gov_parametros.csv` trae **los 1,321 parámetros** de todos los gobernadores en formato
  largo, por si hay que reconstruir la respuesta primaria completa en PSID.

> Implicación: la reserva AGC **no se puede separar de la RSF con datos de PF** — no está
> modelada. Si se quiere una reserva AGC explícita en el UC, el dato tiene que venir del
> MODOM o del Organismo Coordinador, no de este proyecto.

## P5 — Hidro

`hidro_parametros.csv`: **25 máquinas hidráulicas** (identificadas por su modelo de
gobernador), con 115 columnas — todos los parámetros de sus gobernadores aplanados como
`<modelo>.<param>`, más `sgn_MVA`, `P_nominal_MW` e `iturbo`.

**No hay salto/head ni caudal como magnitudes físicas**: los HYGOV del modelo exponen
`At` (ganancia de turbina), `qnl` (caudal en vacío, pu), `Tw`, `r`, `Tr`, `Tg`, `Dturb`
y el estatismo — todo en **pu**, no en m ni m³/s. Los `pmu_TrWHydroFrancis` (4 máquinas)
añaden `Zw`, `h0`, `Rs`, `Rd`, `pt0` (columna de agua en pu). Modelos presentes:
`gov_HYGOV` (11) + variantes por central (Monción, Tavera, Los Toros, Las Damas, Jiguey)
y `pmu_TrWHydroFrancis` (4).

> Implicación: **η agua→MWh no es derivable desde PF**. Sirve para la dinámica (Fase 5),
> no para la economía; la eficiencia económica sigue teniendo que salir del MODOM.

## P6 — Arrays FRT / oarray

`oarray_frt_completo.csv` (formato largo, con columna `origen`) + `oarray_frt_resumen.csv`
(una fila por array con `legible` y `modelo_encriptado`).

**Se resolvió el misterio de los ~90 warnings de la Ronda 1.** Dos causas distintas:

1. **Accesor equivocado** — el valor no está en el parámetro (`oarray_xxx` devuelve vacío)
   sino en un objeto **`IntMat` hijo** del `ElmDsl`, cuyo nombre es el del parámetro **sin
   el prefijo** `array_`/`oarray_`. Enlazándolos se recuperan **70 arrays con 936 valores**:
   curvas de protección de parques eólicos (`TuunderuWT`, `TuoveruWT`, `TfunderfWT`,
   `TfoverfWT`), límites de corriente (`ipmaxuWT`, `iqmaxuWT`), límites Q (`qmaxpp`,
   `qminpp`, `qmaxuu`, `qminuu`), control P (`wp`) y las tablas del governor MAN de las
   barcazas (`Ptable`, `Itable`, `NRGME`, `deltaME`).
2. **Modelos DSL encriptados** — 110 arrays pertenecen a modelos marcados
   `"001! Encrypted model; Editing not possible."`. Ahí caen los `array_LVRT`, `array_HVRT`,
   `array_PFP` y `array_QU` de las **plantas solares** (Monte Plata Solar, PF Martí,
   Maranatha…). El accesor `matrix:array_LVRT` responde con la forma correcta (4 filas)
   pero **vacía**: el dato está cifrado dentro del modelo del fabricante.
   **No es recuperable por API** — solo por la GUI, si el fabricante lo permite, o pidiendo
   la hoja de datos.

Quedan además 20 arrays vacíos en modelos **no** encriptados (`array_vchar` de NEYPRIC 1500,
`array_ytat` de pmu_TrWHydroFrancis, `array_duTCRB`): son tablas realmente sin cargar en
este proyecto, no un problema de lectura.

---

## Qué desbloquea cada cosa (resumen para la sesión de la PC principal)

| Quiero… | Uso… |
|---|---|
| Cerrar el residuo del radial Este | **`escenario_P20_tensiones_flujo.csv`** (5,150 barras, comparación directa) + `escenario_P20_shunts.csv`. Ojo: solo 28 Mvar en el Este y PF ya resuelve Higüey a 0.9017 pu — **descartar barras no energizadas antes de calcular \|ΔV\|**. |
| Límites de Q reales por unidad | `escenario_P20_qcap.csv` (`Qmin/Qmax_actual_Mvar`); curvas solo para 5 unidades |
| Validar Sienna por escenario / R² por escenario | `op_*_P01_P24.csv` + `resumen_por_escenario.csv` |
| Reserva AGC separada | **No sale de PF** (no hay AGC modelado). Proxy primario en `agc_participacion.csv` |
| η hidro económica | **No sale de PF**; los parámetros físicos disponibles están en `hidro_parametros.csv` |
| FRT de eólicos | `oarray_frt_completo.csv` (70 arrays). Solares: encriptados, no recuperables |

## Notas de método (por si hay Ronda 3)

- `GetAttribute("matrix:<param>")` es el accesor válido para arrays de DSL; devuelve la
  forma aunque esté vacío, lo que permite distinguir "no existe" de "vacío".
- Los `IntQlim` guardan la curva en `cap_P`/`cap_Qmn`/`cap_Qmx` con `inputmod` marcando
  las unidades; muchas curvas están declaradas pero vacías.
- `ElmStactrl.psym` puede traer huecos (`None`) — hay que filtrarlos antes de recorrer.
- El flujo de carga se corrió en sandbox (`SBX_R2_<stamp>`) y se borró; las columnas
  `*_actual_*` vienen de `m:Q:bus1` / `m:P:bus1` tras `ComLdf.Execute()` (err=0).
