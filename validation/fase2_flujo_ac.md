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

## Residuo (para siguiente pasada, no bloqueante)

Concentrado en el **radial Este 69 kV** (Higüey −0.055, Bení/Chavón/Bella
Vista/La Romana/Guaymate −0.04) y cola dispersa ≈0.01. Hipótesis, en orden:
1. Estados de **shunts conmutables y SVC por escenario** (iopt_asht=1; el
   Bloque I no los incluyó — pedir `paso_actual` de ElmShnt y consigna SVC en P20)
2. Curvas de capacidad Q reales de las unidades del Este (CESPM/Sultana/
   San Pedro Bio) vs los límites planos de `tipos_generadores`
3. Cabecera del radial (trafos La Romana/SPM 138/69): verificar match de tap
   por `ruta` y si alguno es ElmTr3 (no modelado)

## Reproducir

`julia --project=. scripts/02_powerflow_validation.jl` — construye el System
físico con `op_dir` (Bloque I), aplica el control secundario iterativo
(`solve_with_controls!`) y compara contra `referencia_loadflow.csv` por
`for_name` (detalle en `fase2_delta_v.csv`).
