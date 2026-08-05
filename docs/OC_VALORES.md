# De dónde toma el OC los valores y cómo los calcula

Barrido de la metodología del OC (documento "Programación de la Operación de
Corto Plazo", transcrito en `data/raw/programacion_corto_plazo_...md`, §8) y de
`model_options.csv`. Responde: para cada insumo, **fuente** y **cálculo**, y si
está disponible localmente o es un dato certificado (VEROPE → tipo B).

## Escalares del modelo — TODOS locales (`commitment/model_options.csv`)
| Parámetro | Valor | Significado | Ya en Sienna |
|---|---|---|---|
| `PORCPERD` | **0.006** | uplift de pérdidas base (0.6%) sobre la demanda | ⚠️ usé r·f² (ver nota) |
| `RRPF` / `RRSF` | **0.03** / 0.03 | requisito de reserva RPF/RSF (3%) | ✅ exacto |
| `CENS` | 2 000 000 | costo de energía no suministrada | ✅ exacto |
| `CVER` | 0.001 | costo de vertimiento | pendiente |
| `SBASE` | 100 | base MVA | ✅ |
| `MMAXAGC` | 1.0 | máximo AGC del sistema | dato para el AGC (gap B) |
| `OPCPERD`/`OPCDO` | 1 / 1 | calcular pérdidas / despacho optimizado ON | ✅ |
| `FLUJO_DC_AC` | 0 | red DC (no AC) en el despacho | ✅ |

## Cómo calcula el OC (secuencia de SOLVE, §8.1)
1. **Inicio**: `RF`, `DIFANG=0`, `Demanda × (1 + PORCPERD)` ← pérdidas como **uplift flat 0.6%**.
2. **SOLVE 1** (RMIP, min COSTEST): despacho inicial → precios marginales PMSN.
3. **SOLVE 2** (MIP): **pérdidas** vía `DIFANG = ANGi − ANGj` (linealización eq. 29
   alrededor de Δθ_ref) → CMG, desabastecimiento. ← **es el lazo de pérdidas**.
4. **SOLVE 3/4** (LP): escalones de RPF, asignados **por empresa** (acuerdos
   intraempresa) y **por factor A** — no un simple 3% agregado.
5. Iteración NCV ↔ OPLM con los factores de nodo (FNPROM).

> **Nota de pérdidas**: el OC parte de 0.6% flat y refina con la linealización
> marginal (eq. 29, Δθ_ref), NO con el cuadrático completo `r·f²`. Mi lazo usó
> `r·f²` (efectivo ~9%) que da un costo muy cercano a MODOM porque absorbe
> también el uplift OPLM. **Refinamiento posible**: calibrar a `PORCPERD` +
> linealización marginal para separar pérdidas de OPLM.

## Valores CERTIFICADOS por VEROPE (tipo B — no en la capa canónica)
"VEROPE = Verificación de Restricciones Operativas… parámetros **certificados**,
Art. 35 Res. SIE-061-2015" (§tabla de glosario). De aquí salen, y NO están en el
workbook procesado:
- **CVP declarado** por unidad + **combustible** → sí tenemos `declared_cvp.csv` (Grace).
- **Costo de arranque `C^ARR`** → certificado, NO tabulado en `e_datgen` → **falta**.
- **RENDH (η hidro)** para convertir generación↔agua (eq. 34-35, `P·1/η`) →
  columna existe en gen_params pero **0 unidades poblada** → **falta**.
- Restricciones operativas (TARR, TPAR, TMO, NAMX…) → **sí** en gen_params.

## Conclusión para los gaps
- **Pérdidas**: cerrado y alineado con el método del OC (SOLVE 2); calibración
  fina a PORCPERD posible.
- **Reservas 3%**: exacto (RRPF/RRSF).
- **AGC**: `MMAXAGC=1.0` da el tope agregado, pero falta la participación por
  unidad → sigue tipo B.
- **Embalses / η**: RENDH no poblado → **tipo B** (pedir a VEROPE/OC).
- **Costo de arranque**: certificado VEROPE → **tipo B**.

## Verificación en la VEROPE local (`VERIFICACION CVP_*.xlsx`)
Barrido de la hoja **"COSTO VARIABLE DE PRODUCCIÓN"** — columnas reales:
`PERIODO, EMPRESA, CENTRAL, COMBUSTIBLE, PRECIO COMBUSTIBLE, TRANSPORTE, PRECIO
PUESTO EN PLANTA, CONSUMO ESPECÍFICO, COSTO VAR COMBUSTIBLE, COSTO VAR NO
COMBUSTIBLE, CVP, COMBUSTIBLE ALMACENADO, TASA, PODER CALORÍFICO INFERIOR,
RENDIMIENTO, DENSIDAD`.

Conclusiones (definitivas):
- **RENDIMIENTO / CONSUMO ESPECÍFICO / PODER CALORÍFICO**: sí están, pero son la
  **eficiencia TÉRMICA** (heat-rate) para calcular el CVP — no la **η hidro**
  (agua→MWh) del balance de embalse. La hidro no quema combustible → su η no está
  en la VEROPE. **Embalses siguen bloqueados** (falta η_h del OC).
- **Costo de arranque**: **NO hay columna de arranque** en la VEROPE. Confirmado:
  `C^ARR` no se publica en workbook ni VEROPE → valor certificado interno del OC
  (probablemente en una resolución/anexo aparte) → **tipo B duro**.
- **CVP / combustible / heat-rate térmico**: disponibles (ya vía `declared_cvp`).

**Resumen del barrido**: todo lo que el OC calcula con datos públicos ya lo
tenemos o lo replicamos (pérdidas SOLVE 2, reservas 3%, CVP). Los dos únicos
faltantes (`C^ARR`, `η_h` hidro) **no están en ningún archivo publicado** del
Dropbox del OC — son insumos certificados que habría que pedir directamente.

## Búsqueda en fuentes externas (OC / SIE / EGEHID)

### Costo de arranque `C^ARR`
- **Metodología pública**: la **Norma Técnica de Coordinación y Operación**
  (SIE) rige la declaración; el generador lo declara al OC "desde construcción
  hasta 24 h tras entrada en operación".
- **Valores por unidad**: NO se publican en un dataset abierto; son declaración
  interna al OC (entran en el programa semanal RPSO). → seguir como **tipo B**;
  la vía es solicitarlos al OC o extraer el `C^ARR` del propio MODOM en la VM.

### η hidro (agua→MWh) — **hay fuente pública**
- **datos.gob.do → EGEHID** (Portal de Datos Abiertos RD) publica:
  - **Niveles medios mensuales por embalse** (2024-2026)
  - **Horas de operación por central** (2017-2021)
  - Producción/generación hidroeléctrica
- **egehid.gob.do → "Histórico de Generación Hidroeléctrica"**.
- **Cómo derivar η_h**: con generación (MWh) y extracción/nivel de embalse (hm³)
  por central del portal → η_h ≈ MWh / hm³. Alternativa física: η_h = g·H·η_turb
  con el **salto H** por central (Tavera, Jigüey, Pinalito 50 MW, etc.).
- ⚠️ El portal `datos.gob.do` respondió **geo-bloqueado** desde aquí (HTTP 473);
  **desde RD Fernando sí puede descargarlo**. Ese es el paso para desbloquear
  los embalses sin la VM.

Fuentes: [OC Programación del SENI](https://www.oc.do/Informes/Operaci%C3%B3n-del-SENI/Programaci%C3%B3n-del-SENI) ·
[EGEHID datos.gob.do](https://datos.gob.do/es/organization/empresa-de-generacion-hidroelectrica-dominicana-egehid) ·
[EGEHID histórico generación](https://egehid.gob.do/historico-de-generacion-hidroelectrica/)

## API del OC (`apps.oc.org.do/wsOCWebsiteChart/Service.asmx`) — **alcanzable**
Descubierta vía el repo `FCornielle/oc_cmg`. A diferencia de `datos.gob.do`
(geo-bloqueado), esta API **responde desde aquí** (probado: HTTP 200) y tiene
**59 métodos JSON** (param `Fecha=YYYY-MM-DD`, algunos `Filtro`).

- **NO tiene** embalse/producible/arranque → η hidro y `C^ARR` siguen bloqueados.
- **SÍ desbloquea la VALIDACIÓN (tipo D)** contra el despacho/precios REALES del OC:
  - `GetCentralMarginalPonderadaJSon` — CMG por central×hora ✅ (probado, devuelve datos)
  - `GetPostDespachoJSon` — despacho real por central×hora
  - `GetProgramaOperativoJSon` / `GetPredespachoJSon` / `GetRedespachoJSon` — programa del OC
  - `GetGeneracionProducidadTecnologiaJSon` — generación real por tecnología (mix)
  - `GetMargenesRPFPonderadoJSon` / `GetReservaFriaJSon` / `GetReservaCalienteJSon` — reservas
  - `GetDisponibilidadDeclaradaJSon` — disponibilidad declarada por unidad

→ Con esto se puede comparar **cuantitativamente** el despacho de Sienna contra
el del OC (cierra el gap D), tirando los datos directamente.

## Embalses / η hidro — RESUELTO con el código GAMS del MODOM

El zip `MODOM DIARIO - 422` trae el **código fuente GAMS** del modelo del OC
(`MODOM_NV_70PD(OPLM).gms`) + el workbook V422. Eso cierra el gap de embalses:

- **`RENDH = 1` para todas las hidro** (`e_datgen`). En el balance de embalse
  (`PG·(1/RENDHID)`), eso significa que los niveles/aportes del MODOM **ya están
  en energía-equivalente (MWh), no en hm³** → la conversión agua↔MWh es identidad.
  El "gap de η" era un mal-entendido de unidades.
- **Presupuesto de energía diario** = `DAT_NFIN(EMBALSE,'48')` (= `final_level.csv`).
  GAMS línea 743: `SUM((N,HD), PG·HID_EMB) =L= DAT_NFIN` → la generación hidro
  diaria de cada embalse **no puede exceder ese tope**. Verificado: toda central
  cumple `gen_MODOM ≤ DAT_NFIN` (Tavera 359≤384, Jigüey 395≤423…).
- **Cascada aguas abajo** (`REST_AGUAS_ABAJO`) y **VALOR_AGUA** (dual del balance)
  gobiernan la coordinación *semanal* del agua.

Implementado en `scripts/03` (flag `HYDRO_BUDGET=1`): la hidro pasa de fija a
optimizarse bajo `Σ_t PG ≤ DAT_NFIN` por embalse. Con VALOR_AGUA=0 Sienna llena el
presupuesto (3168 MWh vs MODOM 2982) porque en un día aislado la hidro es gratis.

**VALOR_AGUA (valor del agua, refinamiento)**: el MODOM calcula `VALOR_AGUA` como
el dual del balance de embalse (costo de oportunidad del agua para días futuros).
Se añadió como costo de oportunidad de la hidro en el objetivo del ED
(`ENV["VALOR_AGUA"]`, RD$/MWh): la hidro solo corre cuando el CMG supera ese valor
→ **conserva agua en horas baratas (solar) y la concentra en la punta**. Calibrado:
**V≈5000 RD$/MWh reproduce el uso del MODOM** (Sienna 2987 vs 2982 MWh; barrido
V=0→3168, V=2000→3125, V=5000→2987), y baja la desviación de costo de −12.2% a
−10.2%. Detalle en `validation/hidro_presupuesto.csv`.

> **Costo de arranque C^ARR**: el GAMS confirma que **no es un costo declarado** —
> el arranque se modela como combustible durante `TARR` horas (CVP×PMN×TARR), que
> es justo lo que ya hace `build_modom_system.jl`. Gap cerrado por confirmación.

### Validación implementada (`scripts/15_validacion_oc.jl`, fecha del modelo 30-09-2025)
- **Energía total**: OC 81.4 vs Sienna 82.4 GWh (+1.3%). Por grupo (= subtotales
  publicados por el OC): térmica −8.2%, solar +9.8%, hidro +6.5%.
- **Por central (unidad×hora, matcheo directo por nombre MODOM)**: 71 unidades,
  **R²=0.746, MAE=16 MW**. Las mayores diferencias son pares de la misma planta en
  modo de combustible opuesto (**Quisqueya 2 FO↔GN**, MWh casi iguales) → el
  despacho es correcto; difiere el combustible declarado (dual-fuel).
- **Eólica** se aparta (perfil canónico ≠ clima real del día de bajo viento).
- **Barrido multi-día** (14 días, 17→30-09-2025) contra el despacho fijo de
  Sienna: R²(central) medio **0.727** [0.442, 0.803], estable ~0.70–0.80 en días
  laborables; los días de menor energía (fin de semana, 26–28) bajan por la
  diferencia de demanda (mi día canónico es martes), no por el modelo.

> **CMG/precios NO validados**: el endpoint `GetCentralMarginalPonderadaJSon`
> devuelve "DESABASTECIMIENTO" plano (10096 RD$/MWh) en 13 de 24 horas —
> incluido en la madrugada de mínima demanda, donde es físicamente imposible—.
> No es un CMG limpio, así que la validación se hace sobre **cantidades** (MW),
> no precios. Mi CVP sí está en RD$/MWh (rango 0–17822), comparable si aparece
> una referencia de CMG fiable.
