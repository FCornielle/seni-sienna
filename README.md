# SENI-Sienna

Recreación del **SENI** (Sistema Eléctrico Nacional Interconectado, República Dominicana) en **[Sienna](https://sienna-platform.github.io/Sienna/)**, la plataforma open-source de modelado de sistemas de potencia de NREL (Julia, BSD-3).

El SENI abastece a la República Dominicana con ~3.600 MW de demanda pico sobre una
red de 717 barras (líneas de 230, 138 y 69 kV) y un parque de generación térmico,
hidroeléctrico y renovable. Este proyecto lo reconstruye en una sola herramienta
open-source en Julia y lo somete a los estudios que hoy se hacen con software
comercial, contrastando cada resultado contra las referencias reales del sistema.

Unifica en una sola plataforma lo que hoy hacen dos proyectos separados:

- [Feasibility-Study](https://github.com/FCornielle/Feasibility-Study) — estudios eléctricos (flujo de carga, contingencias, cortocircuito, estabilidad) sobre el modelo PowerFactory del SENI
- [modom-pypsa](https://github.com/FCornielle/modom-pypsa) — réplica del despacho diario del Organismo Coordinador (MODOM) en PyPSA + pandapower

## Qué hace

A partir de la red y las tablas de costos/reservas del SENI, la plataforma corre,
en secuencia, la cadena completa de estudios de operación:

- **Despacho económico y unit commitment** — decide, hora a hora, cuánto genera cada
  unidad al mínimo costo, con arranques, rampas, tiempos mínimos y reservas primaria,
  secundaria-AGC y fría co-optimizadas (LP/MILP sobre red DC).
- **Flujo de carga AC** — resuelve tensiones y flujos sobre la red física completa,
  con control secundario de tensión y límites de reactiva.
- **Contingencias N-1** — evalúa la salida de cada elemento de transmisión (screening
  con factores de distribución LODF, verificación AC en las críticas) y emite un
  veredicto según el Código de Conexión (Ley 125-01).
- **Cuasi-dinámico 24 h** — una secuencia de flujos AC con el perfil horario.
- **Dinámica (RMS y pequeña señal)** — respuesta de frecuencia ante la pérdida del
  mayor generador (nadir vs. el esquema de deslastre EDAC), amortiguamiento de los
  modos electromecánicos y trayectoria de cada máquina, con modelos de gobernador,
  AVR e inversores.
- **Embalses, precios nodales y validación** — balance de energía hidro con valor del
  agua, costo marginal (CMG) por hora, y comparación cuantitativa contra el despacho
  y los precios **reales** publicados por el Organismo Coordinador.

Todo se orquesta desde un **dashboard web** (abajo) que lanza cada estudio y grafica
los resultados. El detalle de fases, arquitectura y criterios de validación está en
[PLAN_SENI_SIENNA.md](PLAN_SENI_SIENNA.md).

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

SPA React-compatible (Preact + htm, sin build) servida por Oxygen, **12 pestañas**:
- **Operación**: KPIs, mix por combustible horario y heatmap de commitment
- **Mapa**: las 678 barras georreferenciadas sobre Leaflet, con capas de nivel de
  tensión, tensión del flujo AC (pu), tensión por hora y deslastre EDAC
- **Despacho**: despacho por central y comparación vs MODOM
- **Dinámica**: pequeña señal (modos) y respuesta de frecuencia
- **Estabilidad**: trayectorias RMS por generador (frecuencia y ΔP) ante la pérdida de PC2
- **Precios**: costo marginal (CMG) nodal y validación de CVP vs la Lista de Mérito del OC
- **Validación OC**: despacho/mix real del OC (API) vs Sienna, por grupo, combustible y central
- **Escenario** (*Scenario Studio*): perillas de demanda, reserva y unidades fuera
  de servicio → UC alternativo con delta vs la línea base
- **Metodología**: ecuaciones MODOM (KaTeX) ↔ implementación Sienna + criterios
- **Corridas**: lanza cualquier corrida (01–17) con un clic, estado y log en vivo
- **Reporte** · **Datos**: reporte consolidado y procedencia de cada insumo

El frontend (`dashboard/spa/`) usa un stack vendorizado localmente
(Preact/htm/Leaflet/KaTeX en `spa/vendor/`) porque la red bloquea npm; no requiere
`npm install` ni build. Ver `docs/EJECUTABLE.md`.

Para arranque en segundos, compilar una vez la sysimage:

```powershell
julia --project=. scripts/13_build_sysimage.jl   # ~30–60 min, una sola vez
```

Para distribuir sin Julia instalado, un **ejecutable standalone**:

```powershell
julia --project=. scripts/18_build_app.jl        # create_app → build_app/SENI-Sienna.exe
```

## Capturas

**Operación** — KPIs del sistema, mix de despacho por combustible y commitment horario:

![Operación](docs/img/operacion.png)

**Mapa** — el SENI georreferenciado: 678 barras y 818 ramas por nivel de tensión
(230 kV rojo · 138 kV azul · 69 kV verde) sobre basemap oscuro:

![Mapa de la red](docs/img/mapa.png)

**Estabilidad** — respuesta transitoria ante la pérdida de Punta Catalina 2 (360 MW):
frecuencia del COI (nadir 59.43 Hz, sobre el escalón EDAC de 59.2 Hz) y la potencia
que aporta cada generador (inercia + governor):

![Estabilidad](docs/img/estabilidad.png)

**Precios** — costo marginal (CMG) nodal por hora y validación del CVP contra la Lista
de Mérito definitiva del OC (Pearson 0.923):

![Precios / CMG](docs/img/precios.png)

**Validación OC** — despacho real del OC (API `apps.oc.org.do`) vs Sienna, por grupo,
combustible y central, más la representatividad multi-día:

![Validación OC](docs/img/validacion-oc.png)

**Despacho** — despacho por central y comparación vs MODOM:

![Despacho](docs/img/despacho.png)

## Estructura

| Ruta | Contenido |
|---|---|
| `src/` | Módulo `SeniSienna`: traductor PowerFactory/MODOM → PowerSystems.jl, capa dinámica y veredictos |
| `scripts/` | Un script por estudio (`01` build … `08` transitorios) + N-1, EDAC, dashboard, validación OC y empaquetado |
| `dashboard/` | Frontend del panel (SPA Preact + htm, sin build) |
| `data/raw/` | Datos confidenciales del modelo y del OC (no versionados — ver su README) |
| `data/sys/` | System serializado (`to_json`) |
| `validation/` | Comparativas vs PowerFactory, MODOM y el OC real |
| `test/` | Tests del traductor |

## Validación

Cada estudio se contrasta contra tres referencias independientes: el optimizador
**MODOM** (despacho del OC), el modelo **PowerFactory** (red y dinámica) y los
resultados **reales publicados por el OC** (API + programa semanal). Las tablas y
figuras de contraste viven en [`validation/`](validation/); el detalle metodológico,
en [PLAN_SENI_SIENNA.md](PLAN_SENI_SIENNA.md) y en el reporte consolidado
`validation/REPORTE_SENI_SIENNA.md`.

## Licencia y datos

Código bajo el módulo `SeniSienna` (Julia). Los datos del modelo —exportaciones de
PowerFactory, tablas MODOM y datos del OC— son **confidenciales** y **no** se
versionan en este repositorio; ver `data/raw/README.md` para colocarlos localmente.
