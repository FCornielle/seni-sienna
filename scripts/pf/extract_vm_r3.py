# -*- coding: utf-8 -*-
"""Extractor Ronda 3 (mini) — tensiones de referencia P01–P24 (SOLO LECTURA).

Especificación: EXTRACCION_VM_RONDA3.md (raíz del repo).
Extiende a los 24 escenarios lo que la Ronda 2 dejó solo para P20
(`escenario_P20_tensiones_flujo.csv`), para poder validar el flujo AC de la
Fase 2 por escenario.

Método: para cada escenario P01…P24 → activar → `ComLdf.Execute()` (con las
opciones del study case BASE, heredadas por la copia sandbox) → leer `m:u` y
`m:phiu` de cada `ElmTerm`.

Salida: data/raw/salida_tensiones_P01_P24_<stamp>/
    tensiones_P01_P24.csv     formato largo (barra × escenario)
    resumen_tensiones.csv     por escenario: nº barras, energizadas, Vmin/media/máx
    _META.json / _WARNINGS.txt

Solo lectura: todo el barrido ocurre dentro de un study case sandbox que se
borra al final; el escenario activo se restaura a P20.

Uso:  python scripts/pf/extract_vm_r3.py [--salida data/raw]
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime
from pathlib import Path

PF_PYD = r"C:\Program Files\DIgSILENT\PowerFactory 2024\Python\3.9"
PROYECTO = "PDD 30-09-2025"
ESCENARIO_BASE = "P20"
ESCENARIOS = ["P%02d" % i for i in range(1, 25)]


def conectar():
    sys.path.insert(0, PF_PYD)
    import powerfactory

    app = powerfactory.GetApplication()
    if app is None:
        raise RuntimeError("No se pudo obtener PowerFactory")
    app.SetWriteCacheEnabled(0)
    return app


def attr(obj, nombre, default=""):
    try:
        v = obj.GetAttribute(nombre)
        return default if v is None else v
    except Exception:
        return default


def nombre(obj):
    return obj.loc_name if obj is not None and hasattr(obj, "loc_name") else ""


def activar_escenario(app, esc):
    for sc in app.GetProjectFolder("scen").GetContents("*.IntScenario"):
        if sc.loc_name.strip().upper() == esc.upper():
            sc.Activate()
            return sc
    raise RuntimeError("Escenario %s no encontrado" % esc)


def escribir_csv(path: Path, filas):
    if not filas:
        return
    claves = list(filas[0].keys())
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=claves)
        w.writeheader()
        w.writerows(filas)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--salida", default="data/raw")
    ap.add_argument("--escenarios", default="", help="lista separada por comas")
    args = ap.parse_args()

    escenarios = ([e.strip().upper() for e in args.escenarios.split(",") if e.strip()]
                  or ESCENARIOS)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = Path(args.salida) / ("salida_tensiones_P01_P24_%s" % stamp)
    out.mkdir(parents=True, exist_ok=True)
    warnings: list[str] = []

    app = conectar()
    if app.ActivateProject(PROYECTO):
        raise RuntimeError("No se pudo activar el proyecto %s" % PROYECTO)
    activar_escenario(app, ESCENARIO_BASE)
    base_case = app.GetActiveStudyCase()
    print("Proyecto %s | study case base %s" % (PROYECTO, nombre(base_case)))

    # opciones del ComLdf que se van a usar (deben ser las de BASE)
    ldf_base = app.GetFromStudyCase("ComLdf")
    opciones = {k: attr(ldf_base, k, None)
                for k in ("iopt_net", "iopt_pq", "iopt_at", "iopt_asht", "iopt_lim",
                          "iopt_plim", "iPbalancing", "iopt_apdist", "itrlx")}
    print("opciones ComLdf de BASE:", opciones)

    filas, resumen = [], []
    sbx = base_case.GetParent().AddCopy(base_case, "SBX_R3_%s" % stamp)
    if sbx is None:
        raise RuntimeError("No se pudo crear el sandbox")
    try:
        sbx.Activate()
        ldf = app.GetFromStudyCase("ComLdf")
        for esc in escenarios:
            try:
                activar_escenario(app, esc)
            except Exception as e:
                warnings.append("%s: no se pudo activar (%s)" % (esc, e))
                continue
            err = ldf.Execute()
            if err:
                warnings.append("%s: ComLdf devolvió %s (no converge) — "
                                "las tensiones de este escenario no son fiables" % (esc, err))
            n_tot = n_ener = 0
            vs, vs_tx = [], []
            for t in app.GetCalcRelevantObjects("*.ElmTerm"):
                if attr(t, "outserv", 0) == 1:
                    continue
                v_pu = attr(t, "m:u")
                ener = int(isinstance(v_pu, float) and v_pu > 0.01)
                n_tot += 1
                n_ener += ener
                if ener:
                    vs.append(float(v_pu))
                    # la Fase 2 compara solo transmisión (≥69 kV)
                    if float(attr(t, "uknom", 0) or 0) >= 69.0:
                        vs_tx.append(float(v_pu))
                filas.append({
                    "escenario": esc,
                    "for_name": attr(t, "for_name"),
                    "loc_name": t.loc_name,
                    "ruta": t.GetFullName(),
                    "kV_nominal": attr(t, "uknom"),
                    "V_pu": v_pu,
                    "angulo_deg": attr(t, "m:phiu"),
                    "energizada": ener,
                })
            fila_r = {
                "escenario": esc,
                "comldf_err": err,
                "barras": n_tot,
                "energizadas": n_ener,
                "V_min_pu": round(min(vs), 6) if vs else "",
                "V_media_pu": round(sum(vs) / len(vs), 6) if vs else "",
                "V_max_pu": round(max(vs), 6) if vs else "",
                "barras_69kV_mas": len(vs_tx),
                "V_min_pu_69kV_mas": round(min(vs_tx), 6) if vs_tx else "",
                "V_media_pu_69kV_mas": round(sum(vs_tx) / len(vs_tx), 6) if vs_tx else "",
                "V_max_pu_69kV_mas": round(max(vs_tx), 6) if vs_tx else "",
            }
            resumen.append(fila_r)
            print("  %s: err=%s | %d barras (%d energizadas) | Vmin %.4f "
                  "Vmedia %.4f Vmax %.4f"
                  % (esc, err, n_tot, n_ener, fila_r["V_min_pu"] or 0,
                     fila_r["V_media_pu"] or 0, fila_r["V_max_pu"] or 0))
    finally:
        base_case.Activate()
        try:
            sbx.Delete()
            print("Sandbox eliminado")
        except Exception as e:
            warnings.append("no se pudo borrar el sandbox: %s" % e)
        try:
            activar_escenario(app, ESCENARIO_BASE)
            print("Escenario restaurado a %s" % ESCENARIO_BASE)
        except Exception as e:
            warnings.append("no se pudo restaurar %s: %s" % (ESCENARIO_BASE, e))

    escribir_csv(out / "tensiones_P01_P24.csv", filas)
    escribir_csv(out / "resumen_tensiones.csv", resumen)
    meta = {
        "proyecto": PROYECTO,
        "study_case_base": nombre(base_case),
        "escenarios": escenarios,
        "escenario_restaurado": ESCENARIO_BASE,
        "fecha": datetime.now().isoformat(),
        "comldf_opciones": opciones,
        "filas": len(filas),
        "por_escenario": resumen,
    }
    (out / "_META.json").write_text(
        json.dumps(meta, indent=2, ensure_ascii=False, default=str), encoding="utf-8")
    if warnings:
        (out / "_WARNINGS.txt").write_text("\n".join(warnings), encoding="utf-8")
    print("Salida: %s (%d filas)" % (out, len(filas)))


if __name__ == "__main__":
    sys.exit(main())
