# Fase 2 — Validación del flujo AC (System físico vs PowerFactory)

**Estado: CERRADA (barrido 1).** Con el punto de operación P20 exacto (Bloque I
de la VM) y la emulación de los controles reales del load flow de PF, el error
es **|ΔV| medio = 0.00605 pu** (≥69 kV) — mejora de **7×** sobre la primera
versión. 490/759 barras dentro de 0.005 pu; el residuo está localizado.

## Evolución

| Iteración | \|ΔV\| medio | \|ΔV\| máx | Qué se agregó |
|---|---|---|---|
| v0 export crudo | 0.0431 | 0.174 | red fusionada node-breaker |
| + taps fijos | 0.0191 | 0.097 | TapTransformer (106 posiciones) |
| + punto P20 exacto (Bloque I) | 0.0223 | 0.078 | cargas/generación/taps del escenario correcto |
| + controladores de estación (condensador en piloto) | 0.0070 | 0.057 | regulación remota (14 ElmStactrl) |
| + **control secundario iterativo** + límites Q (iopt_lim=1) + piso 0.95 en terminales | **0.00605** | 0.055 | Q fluye desde los terminales reales |

## Lo que resolvió cada hallazgo del Bloque I

- `iopt_pq=0`: cargas de potencia constante en PF → nuestra representación ya
  era correcta (hipótesis de dependencia de tensión descartada).
- `iopt_at=0`: taps fijos del escenario ✓ (los de P20 difieren de los del export).
- `iopt_lim=1`: límites de reactiva activos → lazo PV→PQ implementado.
- **La física que faltaba eran los 15 `ElmStactrl`** (control remoto de nodo
  piloto): 14 aplicados; los 14 nodos piloto quedan a ±0.002 pu de PF, incluido
  el caso Boca Chica donde PF **no** alcanza su consigna 0.94 (satura) y
  nosotros tampoco tras acotar los terminales a ≥0.95 pu.

## Residuo — re-diagnóstico con la Ronda 2 de la VM (2026-08-04)

Concentrado en el **radial Este 69 kV** (Higüey −0.055, Bení/Chavón/Bella
Vista/La Romana/Guaymate −0.04). La extracción de shunts/SVC/tensiones
(`vm-extraccion-2-20260804`) **cierra el diagnóstico**:

1. **Shunts — REFUTADO como causa**. El radial Este tiene solo **2 capacitores
   (28 Mvar)**: Higüey 17 Mvar y La Romana Pueblo 15.6 Mvar. Los 30 shunts del
   sistema son de **1 paso fijo** (`ncapa=ncapx=1`) y **no cambian entre P01–P24**
   (`op_shunts_P01_P24.csv`) — pese a `iopt_asht=1` no hay conmutación que
   reproducir. No hay Mvar "perdidos" que recuperar.
2. **La referencia PF ya está baja ahí**. `escenario_P20_tensiones_flujo.csv`
   (leído directo de `m:u`): **Higüey = 0.9017 pu es el mínimo absoluto** de las
   1,577 barras de 69 kV (media 0.991). Es física del radial, no compensación.
3. **La métrica está limpia**: 0 de las 907 barras comparadas están
   de-energizadas (todas v_pf ≥ 0.5) → el sesgo de islas V=0 no aplica aquí. El
   **0.00605 pu se mantiene**; el residuo Este es una diferencia genuina de
   solución radial (Sienna ~0.85 vs PF ~0.90), no un elemento faltante.

Pistas restantes (menor prioridad): curvas de capacidad Q reales de las unidades
del Este (ahora en `escenario_P20_qcap.csv`) y saturación de los SVC de PVDC
(PF los dejó pasar a 20.5 Mvar sobre su qmax 20).

## Reproducir

`julia --project=. scripts/02_powerflow_validation.jl` — construye el System
físico con `op_dir` (Bloque I), aplica el control secundario iterativo
(`solve_with_controls!`) y compara contra `referencia_loadflow.csv` por
`for_name` (detalle en `fase2_delta_v.csv`).

**Datos ya versionados** (merge de `vm-extraccion-20260717`): el Bloque I vive en
`data/raw/salida_bloqueI_edac_20260717_111009/`. Re-ejecutado 2026-08-04 desde esa
ruta: **|ΔV| medio 0.00605 pu, máx 0.05503** (reproduce exacto). El residuo del
radial Este (Higüey −0.055, Bení/Chavón/La Romana/Guaymate −0.04) **no** es Tr3
(los 3 ElmTr3 son EDM3/San Felipe/Metropolitano, ninguno en el Este) ni tap (La
Romana tap 13, SPM tap 9, ambos ElmTr2 aplicados) → queda como **hipótesis 1**:
estado de **shunts/SVC conmutables** (`iopt_asht=1`), no extraído por la VM →
próxima extracción (`paso_actual` de ElmShnt + consigna SVC en P20).
