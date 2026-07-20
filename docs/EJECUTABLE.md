# Ejecutable y empaquetado

## Cómo se ejecuta hoy (funcional)

**`SENI-Sienna.bat`** es el ejecutable de doble clic: abre el navegador en
`http://localhost:8155` y levanta el dashboard. Detecta y usa la **sysimage
precompilada** (`sysimage/SeniSienna_sys.dll`) si existe → arranque del stack
en **1.3 s** (vs 15.6 s sin ella; medido). Cada corrida lanzada desde el panel
hereda ese arranque rápido.

Requisito: Julia instalado en la máquina (el `.bat` apunta a
`%LOCALAPPDATA%\Programs\Julia-1.12.6`). Para regenerar la sysimage tras
actualizar dependencias: `julia --project=. scripts/13_build_sysimage.jl`.

## Distribución sin Julia (opcional, pendiente)

Para un bundle relocatable instalable en una máquina **sin Julia** se usaría
`PackageCompiler.create_app`. No está hecho porque:

1. Requiere reestructurar el proyecto como paquete con un `julia_main()` de
   entrada (hoy son scripts numerados) — cambio de forma, no de fondo.
2. El bundle de este stack (PowerSystems + PSID + Plots + Oxygen) pesa ~2–3 GB
   y tarda 30–60 min en compilar; la construcción es frágil con tantas
   dependencias nativas (HiGHS, Sundials, GR).
3. El `.bat` + sysimage ya da la experiencia de "ejecutable rápido" en la
   máquina de trabajo, que es el caso de uso actual.

**Camino cuando se necesite** (p. ej. entregar a un operador sin entorno Julia):
- Crear `src/app.jl` con `function julia_main()::Cint … end` que llame al
  servidor del dashboard.
- `create_app(".", "dist/SENI-Sienna"; precompile_execution_file=…,
  include_lazy_artifacts=true)`.
- Empaquetar `dist/` + `data/` + `dashboard/` en un instalador (Inno Setup),
  igual que el `.exe` de modom-pypsa (PyInstaller allí).

## Datos (nunca se empaquetan)

`data/raw/` y `data/sys/` son confidenciales y quedan fuera de git y de
cualquier bundle. El ejecutable los espera presentes en la máquina destino
(ver `data/raw/README.md` y `docs/OC_DROPBOX_FEED.md` para su procedencia).
