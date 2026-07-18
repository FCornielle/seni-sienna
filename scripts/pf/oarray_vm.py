# -*- coding: utf-8 -*-
"""Prioridad 3 — tablas oarray_* / matrices de los DSL de parques eólicos.

El export dinámico previo dejó ~90 warnings de "tablas oarray_* no legibles"
(lookup tables de protección/FRT de Guanillo, Los Guzmancito, ...). Este script
intenta leerlas por tres vías (todas SOLO LECTURA):
  1. GetAttribute del nombre del parámetro (vectores → lista)
  2. objetos ChaVec/IntMat/ChaMat contenidos en el ElmDsl o su BlkDef
  3. GetAttribute fila a fila ("nombre:fila:col")

Salida: data/raw/salida_oarray_<stamp>/dsl_tablas.csv (formato largo:
dsl_ruta, model_name, tabla, fila, columna, valor) + _WARNINGS.txt.

Uso:  python scripts/pf/oarray_vm.py
"""
from __future__ import annotations

import csv
import json
import sys
from datetime import datetime
from pathlib import Path

PF_PYD = r"C:\Program Files\DIgSILENT\PowerFactory 2024\Python\3.9"
PROYECTO = "PDD 30-09-2025"


def conectar():
    sys.path.insert(0, PF_PYD)
    import powerfactory

    app = powerfactory.GetApplication()
    if app is None:
        raise RuntimeError("No se pudo obtener PowerFactory")
    app.SetWriteCacheEnabled(0)
    return app


def attr(obj, nombre, default=None):
    try:
        v = obj.GetAttribute(nombre)
        return default if v is None else v
    except Exception:
        return default


def volcar_tabla(filas, dsl, model, nombre_tabla, valor):
    """Aplana escalar/vector/matriz al formato largo."""
    if isinstance(valor, (list, tuple)):
        for i, v in enumerate(valor):
            if isinstance(v, (list, tuple)):
                for j, vv in enumerate(v):
                    filas.append({"dsl_ruta": dsl.GetFullName(), "model_name": model,
                                  "tabla": nombre_tabla, "fila": i, "columna": j,
                                  "valor": vv})
            else:
                filas.append({"dsl_ruta": dsl.GetFullName(), "model_name": model,
                              "tabla": nombre_tabla, "fila": i, "columna": 0,
                              "valor": v})
    else:
        filas.append({"dsl_ruta": dsl.GetFullName(), "model_name": model,
                      "tabla": nombre_tabla, "fila": 0, "columna": 0, "valor": valor})


def main():
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = Path("data/raw") / f"salida_oarray_{stamp}"
    out.mkdir(parents=True, exist_ok=True)
    warnings: list[str] = []
    filas: list[dict] = []

    app = conectar()
    if app.ActivateProject(PROYECTO):
        raise RuntimeError("No se pudo activar el proyecto")

    dsls = app.GetCalcRelevantObjects("*.ElmDsl")
    print("ElmDsl:", len(dsls))
    n_con_tabla = 0
    for dsl in dsls:
        typ = attr(dsl, "typ_id")
        model = typ.loc_name if typ is not None else ""
        sparams = attr(typ, "sParams", []) or []
        # normalizar: sParams puede venir como lista de strings con comas
        nombres = []
        for s in sparams:
            nombres.extend(p.strip() for p in str(s).split(",") if p.strip())
        tablas = [n for n in nombres if n.lower().startswith(("oarray", "array", "matrix"))]

        # vía 2: objetos tabla contenidos en el propio DSL
        contenidos = (dsl.GetContents("*.ChaVec") + dsl.GetContents("*.IntMat")
                      + dsl.GetContents("*.ChaMat"))
        if typ is not None:
            contenidos += (typ.GetContents("*.ChaVec") + typ.GetContents("*.IntMat")
                           + typ.GetContents("*.ChaMat"))
        for objt in contenidos:
            vec = attr(objt, "vector", None)
            mat = attr(objt, "matrix", None)
            val = vec if vec is not None else mat
            if val is None:
                # probar acceso por filas M:0, M:1...
                val = attr(objt, "M", None)
            if val is not None:
                volcar_tabla(filas, dsl, model, objt.loc_name + ":" + objt.GetClassName(), val)
                n_con_tabla += 1
            else:
                warnings.append(f"{dsl.GetFullName()}: {objt.loc_name} "
                                f"({objt.GetClassName()}) sin vector/matrix legible")

        # vía 1/3: parámetros oarray_* por nombre
        for t in tablas:
            v = attr(dsl, t, None)
            if v is not None:
                volcar_tabla(filas, dsl, model, t, v)
                n_con_tabla += 1
                continue
            # fila a fila
            leidas = []
            for i in range(64):
                vi = attr(dsl, f"{t}:{i}", None)
                if vi is None:
                    break
                leidas.append(vi)
            if leidas:
                volcar_tabla(filas, dsl, model, t, leidas)
                n_con_tabla += 1
            else:
                warnings.append(f"{dsl.GetFullName()}: {t} ilegible por las 3 vías")

    print(f"tablas leídas: {n_con_tabla} | filas: {len(filas)} | warnings: {len(warnings)}")
    if filas:
        with open(out / "dsl_tablas.csv", "w", newline="", encoding="utf-8-sig") as f:
            w = csv.DictWriter(f, fieldnames=list(filas[0].keys()))
            w.writeheader()
            w.writerows(filas)
    (out / "_META.json").write_text(json.dumps(
        {"proyecto": PROYECTO, "fecha": datetime.now().isoformat(),
         "n_dsl": len(dsls), "n_tablas": n_con_tabla, "n_filas": len(filas)},
        indent=2, ensure_ascii=False), encoding="utf-8")
    if warnings:
        (out / "_WARNINGS.txt").write_text("\n".join(warnings), encoding="utf-8")
    print(f"Salida en {out}")


if __name__ == "__main__":
    sys.exit(main())
