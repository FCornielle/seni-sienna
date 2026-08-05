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

## Distribución sin Julia — ejecutable standalone (implementado)

Bundle relocatable para una máquina **sin Julia**, vía `PackageCompiler.create_app`:

```powershell
julia --project=. scripts/18_build_app.jl     # ~30–60 min, una vez
```

Genera `build_app/` (no versionada, ~2 GB) con `bin/SENI-Sienna.exe` + un
`SENI-Sienna.bat` de doble clic. **Distribuir la carpeta `build_app/` completa.**

Cómo funciona:
- **Entry point** `SeniSienna.julia_main()` (en `src/SeniSienna.jl`) — arranca el
  dashboard Oxygen y abre el navegador. Resuelve la raíz de datos/assets
  *frozen-aware*: la carpeta del `.exe` cuando está empaquetado (vía `SENI_ROOT`),
  o el repo en desarrollo. **Verificado**: `julia_main()` levanta el panel en
  `http://localhost:8155` y responde todos los endpoints.
- `scripts/18_build_app.jl` compila el paquete con `create_app` y **copia
  `scripts/ + dashboard/ + data/ + validation/` junto al `.exe`** (create_app
  empaqueta `src/` + el entorno, no los assets); `julia_main` los busca ahí.
- `scripts/12_dashboard.jl` es *frozen-aware* (`ROOT = ENV["SENI_ROOT"]` o
  `@__DIR__`), así corre igual como script o empaquetado.

Notas: el build es pesado y frágil por las dependencias nativas (HiGHS, Sundials,
GR); si falla, correr con `incremental=false`. Para un instalador de un clic se
puede envolver `build_app/` con Inno Setup (igual que el `.exe` de modom-pypsa).
El `.bat` + sysimage (arriba) sigue siendo la vía rápida en la máquina de trabajo.

## Frontend: React-compatible sin build (Preact + htm)

El panel es una SPA en `dashboard/spa/` con arquitectura de componentes
(React-compatible vía **Preact + htm**), mapa **Leaflet** y ecuaciones **KaTeX**.

**Por qué no Vite/Next.js con `npm install`**: la red corporativa bloquea
`registry.npmjs.org` y los CDN de paquetes (jsdelivr, unpkg, cdnjs) — un build
con Vite no es posible en este entorno. Solución: stack **vendorizado localmente**
en `dashboard/spa/vendor/` (preact, htm, leaflet, katex, todos descargados una vez
desde el único CDN alcanzable, JSPM) y cargado con un **import map** — sin build,
sin `node_modules`, sin CDN en runtime. Único requisito de red en runtime: los
tiles de OpenStreetMap para el basemap del mapa (inherente a cualquier mapa).

Si en el futuro se dispone de una red con npm, se puede migrar a un build Vite
estándar; la arquitectura de componentes ya está lista para ello.

## Datos (nunca se empaquetan)

`data/raw/` y `data/sys/` son confidenciales y quedan fuera de git y de
cualquier bundle. El ejecutable los espera presentes en la máquina destino
(ver `data/raw/README.md` y `docs/OC_DROPBOX_FEED.md` para su procedencia).
