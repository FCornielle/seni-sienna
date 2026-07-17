# Fase 5 — Dinámica del SENI en PSID: pequeña señal y respuesta de frecuencia

**Estado: COMPLETA (nivel v1)** — el SENI corre simulaciones dinámicas de punta a
punta en PowerSimulationsDynamics con resultados comparables a PowerFactory.

## Capa dinámica v1 ([src/dynamics_library.jl](../src/dynamics_library.jl))

| Componente | Fuente | Modelo PSID |
|---|---|---|
| Máquina síncrona | **Parámetros REALES del export** (sym_extra.csv: xd, xq, x'd, x''d, T'd0, T''d0, T''q0, H, tipo de rotor) en la base MVA del nodo | GENROU (`RoundRotorQuadratic`) si rotor liso, GENSAL (`SalientPoleQuadratic`) si polos salientes; clásica (`BaseMachine`) si datos incompletos |
| AVR | Típico v1 | SEXS (K=100, Te=0.1) |
| Governor | Típico v1 por tecnología | TGOV1 (térmico/diésel), HYGOV (hidro) |
| PSS | v1 sin señal | PSSFixed |
| Cargas | Impedancia constante (ver hallazgo 2) | StandardLoad (Z) |
| Inversores | v2 pendiente (WECC) | fuera de servicio (13 MW nocturnos) |

64 nodos de generación con dinámica (todo el parque síncrono en línea del escenario).

## Resultados vs PowerFactory (escenario P20)

### Pequeña señal ([scripts/07_small_signal.jl](../scripts/07_small_signal.jl))

| Métrica | Sienna v1 | PowerFactory |
|---|---|---|
| Sistema estable | ✅ | ✅ |
| Modos electromecánicos (0.1–3 Hz) | 148 | 348 (129 máquinas individuales + controles) |
| Modos EM con ζ < 10% | **22** | **26** |
| ζ mínimo | 4.89 % | 2.44 % |

Coherencia estructural notable para una capa con AVR/PSS típicos; el ζ mínimo
mayor es esperable (menos detalle de excitación rápida y agregación por nodo).

### Respuesta de frecuencia ([scripts/08_transient_frequency.jl](../scripts/08_transient_frequency.jl))

Mismo evento que la referencia RMS de PF: **pérdida de Punta Catalina 2 (360 MW)**.

| Métrica | Sienna v1 | PowerFactory |
|---|---|---|
| Nadir COI | **59.463 Hz** | **59.285 Hz** |
| Criterio ≥ 59.2 Hz (Código de Conexión) | CUMPLE | CUMPLE |
| f final (30 s) | 59.80 Hz (recuperación por governors) | — |

Δnadir = 0.18 Hz: explicable por cargas Z (alivio con la caída de tensión),
governors típicos algo más rápidos que los reales y sin EDAC modelado.
Serie completa: `fase5_rms_frecuencia_sienna.csv`.

## Hallazgos técnicos del proceso (importantes)

1. **El slack inicializa por encima de su despacho** (absorbe pérdidas ≈ +25%):
   los límites de válvula del governor deben tener cabeceo o la inicialización
   PSID falla (`x_g1 > V_max`).
2. **Cargas de potencia constante colapsan la red algebraica** tras el evento en
   los bolsones a V≈0.8 pu del escenario (corrector IDA sin convergencia en
   t≈+0.25 s con CUALQUIER combinación AVR/governor). Cargas Z lo resuelve —
   y es más fiel a PF (TypLod con dependencia de tensión).
3. `IDA(linear_solver = :KLU)` para el sistema de 613 estados.
4. Escalera de diagnóstico (AVR × governor) automatizada en el script 08 —
   reutilizable para la calibración v2.

## Hoja de ruta v2 (calibración fina)

- Mapear parámetros reales de AVR/GOV/PSS desde `dsl_parametros.csv` (14,134
  pares ya extraídos): EXAC1/IEEET1/ESAC5A→familia AC; GGOV1/HYGOV/DEGOV1
  nativos de PSID; PSS2A/PSS2B reales
- EDAC por pasos (134 etapas activas de `edac_etapas.csv`) como perturbaciones
- Inversores WECC (REGC/REEC/REPC) para PV/eólica/BESS
- Cargas ZIP con los exponentes reales de TypLod
- Desagregar nodos multi-máquina (hoy: máquina dominante por nodo)
