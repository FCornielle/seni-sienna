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

- [x] Fase 0a — Esqueleto del proyecto y plan
- [ ] Fase 0b — Entorno Julia + datos en `data/raw/`
- [ ] Fase 1 — `System` del SENI (traductor PF + MODOM)
- [ ] Fase 2 — Validación de flujo de carga AC
- [ ] Fase 3 — Despacho ED y UC MILP con reservas
- [ ] Fase 4 — Contingencias N-1 y cuasi-dinámico 24h
- [ ] Fase 5 — Pequeña señal y transitorios (PSID)
- [ ] Fase 6 — Análisis, reportes y cierre de gaps

> ⚠️ Los datos del modelo (exports PowerFactory, tablas MODOM, datos OC) son confidenciales y **no** se versionan en este repositorio.
