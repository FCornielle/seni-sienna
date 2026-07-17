# -*- coding: utf-8 -*-
"""Extractor para la VM con DIgSILENT PowerFactory 2024 (SOLO LECTURA).

Misión y prioridades: ver CLAUDE.md (raíz del repo), sección VM.
Bloques y columnas exactas: docs/EXTRACCION_DINAMICA_DIGSILENT.md.

Uso (en la VM, con el Python del PowerFactory):
    python scripts/pf/extract_vm.py --escenario P20 --salida data/raw

Patrón de conexión tomado del Feasibility-Study (pf_worker/connect.py):
una sola instancia por proceso; no thread-safe.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime
from pathlib import Path

PROYECTO = "PDD 30-09-2025"


def conectar():
    import powerfactory  # requiere PYTHONPATH del PF 2024

    app = powerfactory.GetApplication()
    if app is None:
        raise RuntimeError("No se pudo obtener la aplicación PowerFactory")
    app.SetWriteCacheEnabled(0)
    return app


def activar(app, escenario: str):
    err = app.ActivateProject(PROYECTO)
    if err:
        raise RuntimeError(f"No se pudo activar el proyecto {PROYECTO}")
    # activar el escenario de operación (P01..P24)
    escenarios = app.GetProjectFolder("scen").GetContents("*.IntScenario")
    for sc in escenarios:
        if sc.loc_name.strip().upper() == escenario.upper():
            sc.Activate()
            return sc
    raise RuntimeError(f"Escenario {escenario} no encontrado")


def attr(obj, nombre, default=""):
    try:
        v = obj.GetAttribute(nombre)
        return "" if v is None else v
    except Exception:
        return default


def escribir_csv(path: Path, filas: list[dict]):
    if not filas:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=list(filas[0].keys()))
        w.writeheader()
        w.writerows(filas)


# --------------------------- Prioridad 1: Bloque I ---------------------------

def bloque_i(app, out: Path, warnings: list[str]):
    """Punto de operación exacto del escenario activo + opciones del ComLdf."""
    cargas = []
    for lod in app.GetCalcRelevantObjects("*.ElmLod"):
        cargas.append({
            "for_name": attr(lod, "for_name"),
            "loc_name": lod.loc_name,
            "ruta": lod.GetFullName(),
            "P_MW": attr(lod, "plini"),
            "Q_Mvar": attr(lod, "qlini"),
            "outserv": attr(lod, "outserv"),
        })
    escribir_csv(out / "escenario_cargas.csv", cargas)

    gens = []
    for clase, tag in (("*.ElmSym", "sym"), ("*.ElmGenstat", "genstat")):
        for g in app.GetCalcRelevantObjects(clase):
            gens.append({
                "clase": tag,
                "for_name": attr(g, "for_name"),
                "loc_name": g.loc_name,
                "P_desp_MW": attr(g, "pgini"),
                "Q_desp_Mvar": attr(g, "qgini"),
                "U_consigna_pu": attr(g, "usetp"),
                "num_unidades": attr(g, "ngnum"),
                "outserv": attr(g, "outserv"),
                "ref_slack": attr(g, "ip_ctrl"),
            })
    escribir_csv(out / "escenario_generacion.csv", gens)

    taps = []
    for clase in ("*.ElmTr2", "*.ElmTr3"):
        for t in app.GetCalcRelevantObjects(clase):
            taps.append({
                "for_name": attr(t, "for_name"),
                "loc_name": t.loc_name,
                "clase": clase[-6:],
                "tap_actual": attr(t, "nntap"),
                "outserv": attr(t, "outserv"),
            })
    escribir_csv(out / "escenario_taps.csv", taps)

    # opciones del ComLdf del study case activo (¡clave para la Fase 2!)
    ldf = app.GetFromStudyCase("ComLdf")
    opciones = {}
    for campo in ("iopt_net", "iopt_lod", "iopt_pq", "iopt_at", "iopt_asht",
                  "iopt_lim", "iopt_plim", "iopt_qlim", "iPbalancing",
                  "iopt_fls", "iopt_sim"):
        opciones[campo] = attr(ldf, campo, default=None)
    (out / "comldf_opciones.json").write_text(
        json.dumps(opciones, indent=2, default=str), encoding="utf-8")


# ------------------------ Prioridad 2: EDAC en detalle ------------------------

def edac_detalle(app, out: Path, warnings: list[str]):
    """Por etapa de relé de frecuencia: interruptor disparado y elementos que
    quedan aguas abajo (cargas con P del escenario; también ramas si abre un
    alimentador completo). TODO: resolver topología aguas abajo del interruptor.
    """
    filas = []
    for rel in app.GetCalcRelevantObjects("*.ElmRelay"):
        for frq in rel.GetContents("*.RelFrq"):
            filas.append({
                "relay": rel.loc_name,
                "relay_ruta": rel.GetFullName(),
                "etapa": frq.loc_name,
                "f_arranque_pu": attr(frq, "Fset"),
                "retardo_s": attr(frq, "Tdel"),
                "etapa_outserv": attr(frq, "outserv"),
                "relay_outserv": attr(rel, "outserv"),
                # TODO: interruptor disparado (p_switch/cubículo) y elementos
                # aguas abajo — ver CLAUDE.md Prioridad 2
                "interruptor": "",
                "elementos_aguas_abajo": "",
                "MW_deslastrados": "",
            })
    escribir_csv(out / "edac_detalle.csv", filas)
    warnings.append("edac_detalle: resolver interruptor + aguas abajo (TODO)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--escenario", default="P20")
    ap.add_argument("--salida", default="data/raw")
    args = ap.parse_args()

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = Path(args.salida) / f"salida_vm_{args.escenario}_{stamp}"
    warnings: list[str] = []

    app = conectar()
    activar(app, args.escenario)

    bloque_i(app, out, warnings)
    edac_detalle(app, out, warnings)

    meta = {"proyecto": PROYECTO, "escenario": args.escenario,
            "fecha": datetime.now().isoformat(),
            "archivos": sorted(p.name for p in out.iterdir())}
    (out / "_META.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    if warnings:
        (out / "_WARNINGS.txt").write_text("\n".join(warnings), encoding="utf-8")
    print(f"Extracción en {out}")


if __name__ == "__main__":
    sys.exit(main())
