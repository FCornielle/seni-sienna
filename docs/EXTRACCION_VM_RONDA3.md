# Extracción VM — Ronda 3 (mini): tensiones de referencia P01–P24

Objetivo único: **extender la validación de la Fase 2 (flujo AC) a los 24
escenarios**. Hoy solo P20 tiene tensiones de referencia
(`escenario_P20_tensiones_flujo.csv`, Ronda 2). Se necesitan las de P01–P24 para
comparar `|ΔV|` de Sienna por escenario, no solo en P20.

## Reglas duras (recap de las reglas del proyecto)
1. **SOLO LECTURA**. El flujo corre en un study case **sandbox** que se borra al
   final; **restaurar el escenario activo a P20** al terminar.
2. Una sola instancia de PowerFactory por proceso.
3. `GetAttribute` en `try/except` (atributo ausente → vacío, nunca abortar).
4. Salida en `data/raw/salida_tensiones_P01_P24_<YYYYMMDD>/` CSV **utf-8-sig** +
   `_META.json` + `_WARNINGS.txt`. **Rama nueva** (ver Git).

## Qué extraer

Para **cada escenario P01…P24**: activar el escenario → correr `ComLdf` (con las
**mismas opciones del study case BASE**: `iopt_lim=1`, `iopt_asht=1`, `iPbalancing=0`
— idénticas a P20) → leer de **cada `ElmTerm`** el voltaje resuelto.

**`tensiones_P01_P24.csv`** — formato largo, una fila por barra×escenario:

| columna | contenido |
|---|---|
| `escenario` | P01…P24 |
| `for_name` | código W de la barra (para cruzar con Sienna) — vacío si no tiene |
| `ruta` | ruta PF completa (respaldo de cruce) |
| `kV_nominal` | tensión nominal |
| `V_pu` | **`m:u`** resuelto (pu) |
| `angulo_deg` | `m:phiu` |
| `energizada` | 1 si la barra está energizada; 0 si es isla V=0 |

> Es exactamente el mismo contenido que `escenario_P20_tensiones_flujo.csv` de la
> Ronda 2, pero repetido para los 24 escenarios. Reutilizar ese mismo bucle de
> lectura de `m:u`/`m:phiu`; solo envolverlo en el barrido de escenarios (patrón
> ya usado en `edac_mw_por_escenario` / `op_*_P01_P24`).

**Verificación** (en `_META.json`): por escenario, nº de barras energizadas y el
mínimo/media de `V_pu` (debe reproducir Higüey ≈ 0.90 en P20).

## Git — rama nueva (NO tocar `main`)
```bash
git checkout main && git pull
git checkout -b vm-extraccion-3-tensiones-YYYYMMDD
# correr → data/raw/salida_tensiones_P01_P24_YYYYMMDD/
git add scripts/pf/*.py data/raw/salida_tensiones_P01_P24_YYYYMMDD \
        validation/extraccion_vm_3_YYYYMMDD.md
git commit -m "Extraccion VM ronda 3: tensiones de referencia P01-P24 (flujo AC por escenario)"
git push -u origin vm-extraccion-3-tensiones-YYYYMMDD
```

## Al integrar (en la PC principal)
Con esto, `scripts/02_powerflow_validation.jl` se puede barrer por escenario
(cargar `op_cargas/op_generacion/op_taps` del escenario, resolver, comparar contra
`tensiones_P01_P24` filtrando `energizada=1`) → `|ΔV|` medio/máx por escenario,
cerrando la Fase 2 en los 24 puntos.
