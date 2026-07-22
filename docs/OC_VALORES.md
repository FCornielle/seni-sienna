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

→ Con esto se puede comparar **cuantitativamente** el despacho y los precios de
Sienna contra los del OC (cierra el gap D), tirando los datos directamente.
