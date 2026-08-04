# Extracción VM — Ronda 2

Segunda extracción en la VM con PowerFactory 2024 (proyecto **"PDD 30-09-2025"**).
Cierra el residuo de la Fase 2 y desbloquea validación por escenario, AGC e hidro.
Complementa la Ronda 1 (`validation/extraccion_vm_20260717.md`, Bloque I + EDAC).

## Reglas duras (recap de CLAUDE.md)
1. **SOLO LECTURA**: no modificar, no borrar. Estudios que requieran study case →
   sandbox y limpiarlo (patrón Feasibility-Study). Al barrer escenarios, **restaurar
   siempre a P20** al final.
2. Una sola instancia de PowerFactory por proceso.
3. `GetAttribute` siempre en `try/except` (atributo ausente → vacío, nunca abortar).
4. Salidas: `data/raw/salida_<tema>_<YYYYMMDD>/` en CSV **utf-8-sig**, con `_META.json`
   (proyecto, escenario, conteos) y `_WARNINGS.txt`.
5. **Rama nueva** (no tocar `main`): ver sección Git al final.

> Nombres de atributos PF marcados como *(candidato: `xxx`)* — probar con try/except;
> si no existe, dejar la columna vacía y anotar en `_WARNINGS.txt`.

---

## Prioridad 1 — Shunts y SVC en P20  ⭐ (cierra el residuo del radial Este 69 kV)

El flujo de PF corre con `iopt_asht=1` (ajuste de shunts conmutables activo). Nuestra
Fase 2 no tiene su estado por escenario → el radial Este (Higüey, Bení, Chavón, La
Romana, Guaymate) queda ~0.04–0.055 pu bajo. **Este es el dato de mayor impacto.**

**`escenario_P20_shunts.csv`** — por cada `ElmShnt` (todos, en servicio o no):
- `for_name`, `loc_name`, `ruta`, `barra_for_name` (nudo)
- `shtype` (tipo: R/L/C/RL…) *(candidato: `shtype`)*
- `ncapa` = **paso/escalones en servicio en P20** *(candidato: `ncapa`)* ← lo crítico
- `ncapx` = nº máximo de pasos *(candidato: `ncapx`)*
- `qcapn` = Mvar por paso a tensión nominal *(candidato: `qcapn`)*
- `Q_actual_Mvar` = reactiva real inyectada en P20 *(candidato resultado: `m:Q:bus1`)*
- `ushnm` (tensión nominal), `outserv`
- controlado por (nudo piloto / `ElmStactrl` si aplica) *(candidato: `imode`, `cpCtrlNode`)*

**`escenario_P20_svc.csv`** — por cada SVC (`ElmSvs`, o como esté modelado):
- `for_name`, `barra_for_name`, `qmin`, `qmax`, `usetp` (consigna de tensión),
  `Q_actual_Mvar`, `modo_ctrl`, `outserv`

**`escenario_P20_stactrl.csv`** — por cada `ElmStactrl` (confirmar/completar los 15;
la Fase 2 aplicó 14):
- `for_name`, `rembar` (nudo piloto controlado), `usetp` (consigna),
  `imode` (modo: V/Q/…), máquinas/shunts controlados, reparto de Q

**Verificación**: ΣQ capacitiva de shunts en las subestaciones del Este; nº de
escalones en servicio por barra.

---

## Prioridad 2 — Curvas de capacidad Q de generadores en P20  (afina tensión)

Hipótesis 2 del residuo: usamos límites Q planos del tipo, no las curvas de
capacidad reales (CESPM, Sultana, San Pedro Bio, etc.).

**`escenario_P20_qcap.csv`** — por cada `ElmSym` y `ElmGenstat` en servicio:
- `for_name`, `barra_for_name`, `sgn` (MVA nominal), `cosn`, `P_desp_MW`
- `Qmin_actual`, `Qmax_actual` = límites Q **usados en el flujo P20**
  *(candidato resultado: `c:cQ_min`, `c:cQ_max`)*
- límites del tipo / curva de capacidad *(candidato: objeto `pcapo`, o `q_min`/`q_max`
  en pu de Sgn, `iQorient`)*
- `Q_actual_Mvar` *(candidato: `m:Q:bus1`)*

---

## Prioridad 3 — Puntos de operación P01–P24 completos  (validación por escenario)

Repetir el **Bloque I** (cargas, generación, taps) pero para **los 24 escenarios**,
no solo P20. Habilita comparar despacho/flujo de Sienna por escenario (hoy solo P20)
y el R² por escenario. La maquinaria de barrido ya existe (se usó en
`edac_mw_por_escenario.csv`).

Formato preferido: **archivos largos** con columna `escenario` (P01…P24):
- **`op_cargas_P01_P24.csv`**: escenario, for_name, ruta, P_MW, Q_Mvar, escala, outserv
- **`op_generacion_P01_P24.csv`**: escenario, clase, for_name, barra_for_name,
  P_desp_MW, Q_desp_Mvar, U_consigna_pu, modo_ctrl_av, num_unidades, outserv, ref_slack
- **`op_taps_P01_P24.csv`**: escenario, for_name, clase, tap_actual, outserv

Regla: activar cada escenario → exportar → **restaurar P20** al final.

---

## Prioridad 4 — Participación en AGC / control secundario  (reserva AGC separada)

Hoy el margen AGC se absorbe en la RSF. Falta la lista de unidades AGC y su límite.

**`agc_participacion.csv`** — por unidad y por el control de frecuencia del sistema:
- `for_name`, `participa_AGC` (bool), `factor_participacion` / `banda`,
  `Pmax_AGC` por unidad *(candidato: en `ElmStactrl` de control secundario, o flag de
  gobernador / `iAGC`)*
- setup del sistema: nº de unidades AGC, MW total regulante (MMAXAGC del modelo ya = 1.0)

---

## Prioridad 5 — Hidro: parámetros físicos para η  (si están en PF)

La η económica agua→MWh es del MODOM y puede no estar en PF; extraer lo **físico**
que permita derivarla:

**`hidro_parametros.csv`** — por cada `ElmSym` hidráulico:
- `for_name`, `P_nominal_MW`, tipo de turbina, **salto/head nominal** *(candidato:
  parámetros del gobernador HYGOV: `head`, `qnl`, `at`)*, caudal nominal, eficiencia
  turbina, enlace a embalse si existe.

---

## Prioridad 6 — oarray FRT completo  (parques eólicos)

Completar las tablas `oarray_*` de los `ElmGenstat` eólicos que quedaron con warnings
en la Ronda 1 (`salida_oarray_20260717_231716/_WARNINGS.txt`, ~90 pendientes):
curvas FRT / límites de tensión-tiempo por parque.

**`oarray_frt_completo.csv`** — for_name del parque, tabla oarray (V, t, acción).

---

## Git — rama nueva (NO tocar `main`)

```bash
cd <repo seni-sienna en la VM>
git checkout main && git pull
git checkout -b vm-extraccion-2-YYYYMMDD        # p.ej. vm-extraccion-2-20260805

# ... correr los scripts de extracción, que escriben en:
#     data/raw/salida_shunts_svc_YYYYMMDD/
#     data/raw/salida_op_P01_P24_YYYYMMDD/
#     data/raw/salida_agc_hidro_YYYYMMDD/
#     (cada uno con _META.json y _WARNINGS.txt)

git add scripts/pf/*.py \
        data/raw/salida_shunts_svc_YYYYMMDD \
        data/raw/salida_op_P01_P24_YYYYMMDD \
        data/raw/salida_agc_hidro_YYYYMMDD \
        validation/extraccion_vm_2_YYYYMMDD.md
git commit -m "Extraccion VM ronda 2: shunts/SVC P20 + Qcap + P01-P24 + AGC + hidro"
git push -u origin vm-extraccion-2-YYYYMMDD
```

- `data/raw/` es **excepción autorizada** solo en esta rama de extracción (como en la
  Ronda 1); no se mergea a `main` sin filtrar (en la PC principal integramos solo lo
  necesario, preservando `CLAUDE.md` y los README).
- Documentar en `validation/extraccion_vm_2_YYYYMMDD.md`: qué se extrajo, conteos,
  hallazgos (sobre todo los shunts capacitivos del Este) y qué quedó con warnings.

## Orden sugerido (por impacto/esfuerzo)
1. **P1 shunts/SVC** (poco esfuerzo, cierra Fase 2) →
2. **P2 Qcap** (mismo barrido de generadores) →
3. **P3 P01–P24** (barrido, más pesado) →
4. **P4 AGC** + **P5 hidro** (lectura de atributos) →
5. **P6 oarray** (completar warnings).
