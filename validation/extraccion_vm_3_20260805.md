# Extracción VM — Ronda 3 (mini): tensiones de referencia P01–P24

**Entorno**: VM con PowerFactory 2024, proyecto "PDD 30-09-2025", study case **BASE**,
Python 3.9 + `powerfactory.pyd`. **Script**: `scripts/pf/extract_vm_r3.py`.
Solo lectura: el barrido corrió dentro de un study case sandbox (`SBX_R3_<stamp>`)
que se borró al final, y el escenario activo quedó restaurado en **P20**.
Responde a `EXTRACCION_VM_RONDA3.md`.

**Salida**: `data/raw/salida_tensiones_P01_P24_20260805_115455/`

| Archivo | Contenido |
|---|---|
| `tensiones_P01_P24.csv` | **123,600 filas** (5,150 barras × 24 escenarios): `escenario, for_name, loc_name, ruta, kV_nominal, V_pu, angulo_deg, energizada` |
| `resumen_tensiones.csv` | por escenario: `comldf_err`, nº de barras, energizadas, V min/media/máx **globales y restringidas a ≥69 kV** |

## Verificación

- **Los 24 escenarios convergieron** (`comldf_err = 0` en todos).
- Opciones del ComLdf usadas (heredadas de BASE, idénticas a las de P20 de la Ronda 2):
  `iopt_lim=1`, `iopt_plim=1`, `iopt_asht=1`, `iPbalancing=0`, `iopt_at=0`, `iopt_pq=0`.
- **Higüey reproduce exactamente el valor de la Ronda 2 en P20: 0.901708 pu.** ✅
- 4,668 barras energizadas de 5,150 en casi todos los escenarios (4,667 en P10–P12).

## Hallazgos

### 1. El escenario mueve la tensión más que el residuo que se está persiguiendo ⚠️

Variación de cada barra entre los 24 escenarios (≥69 kV, `Vmax − Vmin`):

| Métrica | Valor |
|---|---|
| **ΔV medio por barra entre escenarios** | **0.0322 pu** |
| Barras con ΔV < 0.01 pu | **0 de 4,087** |
| ΔV máximo | **0.1009 pu** (Higüey) |

Es decir: **ninguna barra de transmisión es insensible al escenario**, y el rango típico
(0.032 pu) es **mayor que el residuo de 0.019 pu** que la Fase 2 intentaba cerrar. Validar
solo contra P20 medía contra un punto muy particular; con estos datos el `|ΔV|` por
escenario dirá si el error de Sienna es estructural o si estaba dominado por la elección
del escenario.

### 2. El radial Este es un fenómeno de carga, no de compensación

Higüey (`WHIGUF`) recorre **0.9896 pu en P08 (valle) → 0.8887 pu en P22 (pico)**:

```
P01 0.9074  P02 0.9209  P03 0.9109  P04 0.9365  P05 0.9606  P06 0.9488
P07 0.9722  P08 0.9896  P09 0.9847  P10 0.9856  P11 0.9861  P12 0.9742
P13 0.9812  P14 0.9846  P15 0.9849  P16 0.9702  P17 0.9682  P18 0.9523
P19 0.9305  P20 0.9017  P21 0.8923  P22 0.8887  P23 0.8916  P24 0.8984
```

Es **la mayor excursión de todo el sistema ≥69 kV** y sigue exactamente la curva de
demanda. Confirma y refuerza el hallazgo de la Ronda 2: en los escenarios de punta
(P20–P24) Higüey es **el mínimo absoluto de la red de transmisión**; en valle no tiene
ningún problema. No es un déficit de capacitores — es la caída del radial bajo carga.
La segunda mayor excursión es Constanza (`WCONSF`, ΔV = 0.096 pu, pero en el rango sano
0.967–1.063).

### 3. Cobertura del cruce por `for_name`

De las 112,029 filas energizadas, **21,813 traen `for_name`** (≈ **909 barras por
escenario**) — que es justo el tamaño del conjunto que la Fase 2 ya comparaba (907 barras).
El resto son terminales internos de subestación sin código W; para ellos hay que usar
`ruta`. **La cobertura del cruce no cambia respecto a P20**, así que la comparación por
escenario es directamente equiparable a la que ya existe.

### 4. Barras no energizadas

482 barras (5,150 − 4,668) resuelven a V = 0 en todos los escenarios: son islas sin
energizar del modelo. Están en el CSV marcadas con `energizada = 0` y **deben filtrarse
antes de calcular cualquier `|ΔV|`** (mismo aviso que en la Ronda 2).

## Cómo usarlo (PC principal)

En `scripts/02_powerflow_validation.jl`, por cada escenario P01…P24:

1. cargar el punto de operación del escenario desde la **Ronda 2**
   (`op_cargas_P01_P24.csv`, `op_generacion_P01_P24.csv`, `op_taps_P01_P24.csv`,
   filtrando por la columna `escenario`);
2. resolver el flujo AC en Sienna;
3. comparar contra `tensiones_P01_P24.csv` filtrando **`energizada = 1`** y cruzando por
   `for_name` (respaldo: `ruta`);
4. reportar `|ΔV|` medio y máximo **por escenario**.

Con eso la Fase 2 queda validada en los 24 puntos y no solo en P20. Sugerencia de lectura
del resultado: si el `|ΔV|` de Sienna se mantiene ~0.019 pu en los 24 escenarios, el
residuo es estructural (modelo); si varía tanto como las propias tensiones de referencia
(0.032 pu de rango), el diagnóstico apunta al punto de operación, no al modelo.
