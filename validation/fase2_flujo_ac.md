# Fase 2 — Validación del flujo AC (System físico vs PowerFactory)

**Estado: infraestructura completa y convergente; validación bloqueada en
|ΔV| medio ≈ 0.019 pu por desalineación de escenario entre el export y la
referencia.** Falta un insumo de la VM (abajo) para cerrar la meta de 0.005 pu.

## Qué se construyó

`build_seni_physical_system` ([src/parse_powerfactory.jl](../src/parse_powerfactory.jl)),
réplica en PowerSystems.jl de la receta AC de modom-pypsa:

- Fusión node-breaker: 5,177 terminales → **718 nodos eléctricos** (union-find por
  interruptores cerrados + jumpers R,X < 0.05 Ω)
- **626 líneas + 177 trafos** (impedancias reales, 0 sin tipo), isla principal del slack
  (Punta Catalina 1); 370 cargas, 25 shunts (signo por tipo), 64 nodos PV, 13 estáticos PQ
- **Taps fijos de escenario** con `TapTransformer` (106/181 trafos con posición ≠ 0);
  convención validada empíricamente (la inversa da 4× peor)
- Límites de Q reales por tipo de máquina (`tipos_generadores.csv`)
- Flujo AC (PowerFlows.jl, Newton-Raphson): **converge en 5 iteraciones**

## Resultados (907 barras comparadas por for_name vs `referencia_loadflow.csv`, P20)

| Iteración | \|ΔV\| medio ≥69 kV | \|ΔV\| máx |
|---|---|---|
| Sin taps | 0.0431 pu | 0.174 pu |
| **Con taps** | **0.0191 pu** | **0.097 pu** |
| + límites Q | 0.0191 pu (PowerFlows no los aplicó en NR) | 0.097 pu |

Detalle por barra: `fase2_delta_v.csv`. Sesgo sistemático: 649 barras bajas vs 148 altas.

## Diagnóstico del residuo

1. **Desalineación de escenario (causa principal)**: la demanda del export
   (3,645 MW) no es la de P20 (3,466 MW, +5.2%); el export se tomó con otro
   escenario activo (P21/pico). Comparamos dos puntos de operación distintos —
   el patrón regional (Este −0.07…−0.10) es consistente con despacho distinto
   de Quisqueya/CESPM/barcazas PAK entre escenarios.
2. Posible dependencia de tensión de las cargas en las opciones del ComLdf de PF
   (nuestras cargas son potencia constante).
3. Controladores de estación (nodo piloto 345 kV → Punta Catalina) y SVC no modelados.
4. PowerFlows NR no aplicó `check_reactive_power_limits` (máquinas al límite de Q
   en PF, p. ej. San Pedro Bio +0.05, no reproducibles aún).

## Para cerrar la meta 0.005 pu — pedir al agente de la VM (Bloque I)

Con el **mismo escenario** (P20) y el mismo study case de la referencia:
1. `escenario_P20_cargas.csv`: por carga (for_name/ruta): P_MW, Q_Mvar
2. `escenario_P20_generacion.csv`: por generador: P_MW, Q_Mvar, U_consigna, en servicio
3. `escenario_P20_taps.csv`: posición de tap por trafo
4. `comldf_opciones.json`: opciones del ComLdf (dependencia de tensión de cargas,
   ajuste automático de taps, límites de reactiva, slack distribuido)

Con eso se re-inyecta el punto de operación exacto y se repite la comparación.
