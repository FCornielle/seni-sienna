# SENI-Sienna

Recreación del **SENI** (Sistema Eléctrico Nacional Interconectado, República Dominicana) en **[Sienna](https://sienna-platform.github.io/Sienna/)**, la plataforma open-source de modelado de sistemas de potencia de NREL (Julia, BSD-3).

Unifica en una sola plataforma lo que hoy hacen dos proyectos:

- [Feasibility-Study](https://github.com/FCornielle/Feasibility-Study) — estudios de interconexión PV+BESS sobre el modelo PowerFactory del SENI
- [modom-pypsa](https://github.com/FCornielle/modom-pypsa) — réplica del despacho diario del OC (MODOM) en PyPSA + pandapower

📋 **Plan completo**: [PLAN_SENI_SIENNA.md](PLAN_SENI_SIENNA.md) — matriz de cobertura, arquitectura, fases, riesgos y criterios de validación.

## Inicio rápido

```powershell
# 1. Instalar Julia (>= 1.10)
winget install --id=Julialang.Julia

# 2. Instalar dependencias Sienna y verificar el entorno
julia scripts/00_setup_environment.jl

# 3. Copiar los datos confidenciales según data/raw/README.md

# 4. Construir el System del SENI (Fase 1)
julia scripts/01_build_system.jl
```

## Dashboard (plataforma de corridas)

```powershell
.\SENI-Sienna.bat          # → http://localhost:8155
```

Panel web estilo modom-pypsa con 5 pestañas:
- **Corridas**: lanza cualquier corrida (01–11) con un clic, con estado y log en vivo
- **Escenario** (*Scenario Studio*): perillas de demanda, reserva y unidades fuera
  de servicio → corre un UC alternativo y muestra el delta vs la línea base
- **Resultados**: galería de figuras + tablas de `validation/`
- **Reporte**: reporte consolidado renderizado
- **Datos**: procedencia de cada insumo (feed del OC)

Para arranque en segundos, compilar una vez la sysimage:

```powershell
julia --project=. scripts/13_build_sysimage.jl   # ~30–60 min, una sola vez
```

## Estructura

| Ruta | Contenido |
|---|---|
| `src/` | Módulo `SeniSienna`: traductor PowerFactory/MODOM → PowerSystems.jl, capa dinámica |
| `scripts/00–08` | Un script por fase: setup, build, power flow, despacho ED, UC MILP, N-1, cuasi-dinámico, pequeña señal, transitorios |
| `data/raw/` | Datos confidenciales (no versionados — ver su README) |
| `data/sys/` | System serializado (`to_json`) |
| `validation/` | Comparativas vs PowerFactory / modom-pypsa / MODOM real |
| `test/` | Tests del traductor |

## Estado

- [x] Fase 0 — Esqueleto, plan, entorno Julia + datos en `data/raw/`
- [x] Fase 1 — `System` de despacho MODOM (717 barras, tests 7/7)
- [x] Fase 2 — System físico AC + flujo de carga (|ΔV| medio 0.019 pu; meta 0.005 pendiente del punto de operación P20 exacto — Bloque I)
- [x] Fase 3a — Despacho ED con commitment fijo (**R² 0.957 vs MODOM**, ENS 0)
- [x] Fase 3b — UC MILP con PSI + reservas RPF/RSF co-optimizadas (commitment 89.9% vs MODOM)
- [x] Fase 4 — Contingencias N-1 (659 evaluadas, LODF + AC en críticas) y cuasi-dinámico 24h (24/24 convergen)
- [x] Fase 5 — Dinámica v1 en PSID: pequeña señal (estable; 22 modos ζ<10% vs 26 en PF) y respuesta de frecuencia (nadir 59.463 Hz vs 59.285 PF, pérdida de Punta Catalina 2)
- [x] Fase 6 — Veredictos del Código de Conexión (`src/verdicts.jl`), reporte consolidado con figuras (`validation/REPORTE_SENI_SIENNA.md`) y gaps documentados (cortocircuito/protecciones → flujo híbrido)
- [x] Barrido 1 — Fase 2 cerrada: |ΔV| medio **0.006 pu** con punto P20 exacto + controladores de estación + límites Q (`validation/fase2_flujo_ac.md`)
- [x] Barridos 2–3 — Sobredeslastre EDAC cuantificado (1.39×; escalón 1 completo 3.2×) y costos de arranque (neutro) (`validation/barrido2_3_edac_arranques.md`)
- [x] v2 dinámica — parámetros DSL reales (23 governors + 32 AVR reales; nadir 59.432 vs 59.285 PF) y **estudio de deslastre selectivo**: 30% por alimentador logra mejor recuperación con 3.3× menos carga interrumpida (`validation/v2_dinamica_selectivo.md`, figura f7)
- [ ] **Hito siguiente: ejecutable + dashboard** (estilo modom-pypsa): corridas ED/UC/N-1/QDS/dinámica desde una UI, sysimage precompilada (arranque en segundos), feed OC integrado (`docs/OC_DROPBOX_FEED.md`) y empaquetado distribuible

> ⚠️ Los datos del modelo (exports PowerFactory, tablas MODOM, datos OC) son confidenciales y **no** se versionan en este repositorio.
