# v2 dinámica (DSL reales) + estudio de deslastre selectivo

## v2 — Parámetros DSL reales en la capa dinámica ([src/dynamics_library.jl](../src/dynamics_library.jl))

Los 14,134 pares parámetro→valor extraídos de la VM ahora alimentan los modelos
PSID (modo `:dsl`, default). Mapeo logrado sobre los 64 nodos:

| Familia | Real completo | Real parcial (droop) | Típico |
|---|---|---|---|
| Governors | 13 HYGOV | 10 GGOV1→TGOV1(r,Tact,Tb reales) + 12 DEGOV1→TGOV1(droop real) | 29 |
| AVR | 11 EXAC1 + 21 IEEET1/ESAC5A (AVRTypeI) | — | 32 SEXS |

**Resultado**: nadir ante pérdida de PC2 = **59.432 Hz** (v1 típicos: 59.463;
PowerFactory: 59.285) — los parámetros reales acercan el nadir a la referencia.

Limitaciones encontradas (anotadas para upstream/v3):
- **PSID 0.15 no implementa `initialize_tg!` para `GeneralGovModel` (GGOV1)** —
  por eso los 10 GGOV1 van a TGOV1 con sus parámetros dominantes reales.
- Los `Vrmax/Vrmin` reales no vienen en el export DSL (el init de PF exige
  V_R ≈ 8–16.5) → límites amplios ±20 en v2.
- Los AVR reales (EXAC1 con saturación) **no re-inicializan tras LoadTrips
  masivos** → los estudios con deslastre corren en capa v1 (SEXS/típicos).
- **Lección crítica de PSID**: el System debe quedar en `DEVICE_BASE` antes de
  `Simulation` — los callbacks de perturbación leen getters de PSY y en
  `NATURAL_UNITS` los deltas quedan ~100× (invalidó la primera corrida del
  barrido 2, ya corregida).

## Deslastre selectivo vs EDAC actual ([scripts/11_deslastre_selectivo.jl](../scripts/11_deslastre_selectivo.jl))

Tres simulaciones (pérdida de PC2, 360 MW; disparos en los tiempos observados
de la referencia PF; capa v1 estable):

| Caso | MW deslastrados | Nadir | Pico f | f final (30 s) |
|---|---|---|---|---|
| A: sin EDAC | 0 | 59.463 | 60.00 | 59.80 |
| B: **EDAC actual** (abrir los 13 alimentadores completos) | **501.6** | 59.463 | **60.44** | **60.08** |
| C: **selectivo** (30% de cada alimentador) | **150.5** | 59.463 | 59.96 | 59.89 |

Figura: `figuras/f7_deslastre_selectivo.png`.

**Lectura (el argumento contra la práctica actual, cuantificado):**
1. El deslastre llega **después del nadir** (los relés disparan a 59.3 Hz + 0.1 s,
   cuando la frecuencia ya tocó fondo y la reserva primaria está actuando) — no
   mejora el nadir en absoluto; solo decide cómo será la recuperación.
2. **EDAC actual**: 1.39× la pérdida → sobrefrecuencia (pico 60.44, se asienta
   en 60.08, por encima de nominal) + 502 MW de usuarios apagados sin necesidad.
3. **Selectivo al 30%**: con **3.3× menos carga** interrumpida logra una
   recuperación MEJOR que la natural (59.89 vs 59.80) sin cruzar jamás 60 Hz —
   deslastrar por fracción de alimentador domina en todos los ejes a abrir
   circuitos completos.
4. Con la dinámica de Sienna (v1 y v2) el nadir ni siquiera cruza 59.30 Hz —
   el EDAC no debería activarse para este evento; que en PF sí dispare
   (nadir 59.285) subraya lo fino del margen del primer escalón.

## Procedencia de datos nuevos

Feed del OC vía Dropbox verificado y documentado en
[docs/OC_DROPBOX_FEED.md](../docs/OC_DROPBOX_FEED.md) — incluye el hallazgo de
la carpeta **5.CASOS DIGSILENT** (fuente pública oficial de los .pfd del SENI)
y la receta técnica de listado/descarga con sus límites.
