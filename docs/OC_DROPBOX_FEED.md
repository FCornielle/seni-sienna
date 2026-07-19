# Feed del OC vía Dropbox — reconocimiento y receta (2026-07-18)

Complemento del pipeline de **Grace** en modom-pypsa
(`docs/oc_programacion_seni.md` de ese repo). Aquí queda lo verificado desde
este proyecto y la receta técnica para automatizar.

## Ruta oficial

`https://www.oc.do/Informes/Operación-del-SENI/Programación-del-SENI` →
la página solo contiene un enlace a un **Dropbox compartido público**:

```
https://www.dropbox.com/sh/sel2bzf89wc3dyu/AADtkkVSXlh1Eb9nSdvZQUbAa?dl=0
```

## Estructura verificada (listado de la raíz, 2026-07-18)

| Carpeta | Contenido |
|---|---|
| 1.PROGRAMACION SEMANAL | PSD semanales (+ reportes RPSO/ASPPSO) |
| 2.PROGRAMACION DIARIA | PDD diarios (xlsx + RPDO pdf) |
| 3.VEROPE | VERIFICACION CVP semanal (CVP declarado + combustible) |
| 4.MISCELANEOS | varios |
| **5.CASOS DIGSILENT** | **casos .pfd del SENI publicados por el OC** (de aquí salen los PDD .pfd) |
| Programacion de la Operacion | documento metodológico |

> El hallazgo relevante para este proyecto es **5.CASOS DIGSILENT**: fuente
> oficial y pública de los casos de red — misma familia que el "PDD 30-09-2025"
> de la VM. Procedencia limpia para futuros refrescos del modelo físico.

## Receta técnica (lo que funciona y lo que no)

- **Listar la raíz** (funciona sin navegador):
  `POST https://www.dropbox.com/list_shared_link_folder_entries` con cookies de
  la página y form `t=<cookie t>`, `link_key=sel2bzf89wc3dyu`, `link_type=s`,
  `secure_hash=AADtkkVSXlh1Eb9nSdvZQUbAa`, `sub_path=` → JSON con las carpetas
  y sus href `/scl/fo/...?rlkey=...`.
- **Listar subcarpetas**: el mismo endpoint NO acepta los links nuevos
  `/scl/fo/` (404) y sus páginas cargan por JS → para archivos individuales
  hace falta navegador (Grace) o la API oficial de Dropbox con token.
- **Descargar una subcarpeta completa**: su href con `&dl=1` entrega un zip
  generado al vuelo (sin Content-Length). **Ojo con el tamaño**: `3.VEROPE`
  supera los 300 MB (histórico completo); `2.PROGRAMACION DIARIA` y
  `5.CASOS DIGSILENT` serán mucho mayores. Descargar carpetas completas solo
  con tope (`curl --max-filesize`) y de forma consciente.

## Qué hay local hoy (procedencia)

| Dato | Archivo local | Origen |
|---|---|---|
| CVP declarado (VEROPE) | `modom-pypsa/data/external/programacion_seni/verope/declared_cvp.csv` | OC Dropbox → Grace (2026-06-14) |
| PDD vigente | `modom-pypsa/data/external/PDD 11-06-26/` (xlsx + RPDO pdf) | OC Dropbox → Grace |
| Red física | export VM PowerFactory "PDD 30-09-2025" | VM DIgSILENT (origen: OC 5.CASOS DIGSILENT) |

## Pendiente para Grace (siguiente visita al Dropbox)

1. VEROPE más reciente (semana en curso) → refrescar `declared_cvp.csv`
2. El PDD del día que se quiera correr en el dashboard
3. Inventario de `5.CASOS DIGSILENT` (nombres/fechas de los .pfd disponibles)

Regla de siempre: guardar con el nombre original del OC + carpeta canónica +
anotar fecha de descarga; nada de esto se versiona en git.
