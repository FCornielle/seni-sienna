# -*- coding: utf-8 -*-
"""RMS de referencia con EDAC habilitado (VM DIgSILENT, patrón sandbox).

Evento: pérdida de Punta Catalina 2 a t=1 s, escenario P20, 30 s de RMS.
Con las protecciones activas, los relés de frecuencia abren sus circuitos;
se detecta qué cargas EDAC quedaron deslastradas monitoreando su P.

Salidas (data/raw/salida_rms_edac_<stamp>/):
    rms_edac_series.csv     t, f de barras clave (m:fehz), speed de máquinas,
                            P de las cargas EDAC monitoreadas
    rms_edac_disparos.csv   carga EDAC → t de disparo y MW abiertos
    rms_edac_output.txt     mensajes del output window (si accesible)
    _META.json / _WARNINGS.txt

SOLO LECTURA sobre la red: todo objeto nuevo se crea dentro del study case
sandbox (copia de BASE) y se borra al final.

Uso:  python scripts/pf/rms_edac_vm.py --escenario P20 --tstop 30
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
GEN_PERDIDO = "Punta Catalina 2"
# terminales a monitorear (m:fehz): todos los de 345 kV + una muestra por nivel
MAX_BARRAS_POR_NIVEL = {345.0: 99, 230.0: 8, 138.0: 10, 69.0: 4}


def attr(obj, nombre, default=""):
    try:
        v = obj.GetAttribute(nombre)
        return default if v is None else v
    except Exception:
        return default


def conectar():
    sys.path.insert(0, PF_PYD)
    import powerfactory

    app = powerfactory.GetApplication()
    if app is None:
        raise RuntimeError("No se pudo obtener PowerFactory")
    app.SetWriteCacheEnabled(0)
    return app


def activar_escenario(app, escenario):
    for sc in app.GetProjectFolder("scen").GetContents("*.IntScenario"):
        if sc.loc_name.strip().upper() == escenario.upper():
            sc.Activate()
            return
    raise RuntimeError(f"Escenario {escenario} no encontrado")


def cargas_edac(app):
    """Cargas disparadas por relés de frecuencia activos (obj_id del cubículo raíz)."""
    cargas = {}
    for rel in app.GetCalcRelevantObjects("*.ElmRelay"):
        frqs = rel.GetContents("*.RelFrq")
        if not frqs or attr(rel, "outserv", 0) == 1:
            continue
        if not any(attr(f, "outserv", 0) == 0 for f in frqs):
            continue
        p = rel.GetParent()
        while p is not None and p.GetClassName() == "ElmRelay":
            p = p.GetParent()
        if p is None or p.GetClassName() != "StaCubic":
            continue
        oid = attr(p, "obj_id", None)
        if oid not in (None, "") and oid.GetClassName() == "ElmLod" \
                and attr(oid, "outserv", 0) == 0:
            cargas[oid.GetFullName()] = oid
    return list(cargas.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--escenario", default="P20")
    ap.add_argument("--tstop", type=float, default=30.0)
    ap.add_argument("--paso", type=float, default=0.01)
    ap.add_argument("--salida", default="data/raw")
    args = ap.parse_args()

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = Path(args.salida) / f"salida_rms_edac_{stamp}"
    out.mkdir(parents=True, exist_ok=True)
    warnings: list[str] = []

    app = conectar()
    if app.ActivateProject(PROYECTO):
        raise RuntimeError("No se pudo activar el proyecto")
    activar_escenario(app, args.escenario)

    base_case = app.GetActiveStudyCase()
    carpeta_casos = base_case.GetParent()
    print(f"Study case base: {base_case.loc_name}")

    # ------------------- sandbox -------------------
    sbx = carpeta_casos.AddCopy(base_case, f"SBX_RMSEDAC_{stamp}")
    if sbx is None:
        raise RuntimeError("No se pudo copiar el study case")
    sbx.Activate()
    print(f"Sandbox activo: {sbx.loc_name}")

    try:
        # generador a perder
        gen = None
        for g in app.GetCalcRelevantObjects("*.ElmSym"):
            if g.loc_name.strip().lower() == GEN_PERDIDO.lower():
                gen = g
                break
        if gen is None:
            raise RuntimeError(f"No se encontró {GEN_PERDIDO}")
        p_pre = float(attr(gen, "pgini", 0) or 0) * max(int(attr(gen, "ngnum", 1) or 1), 1)
        print(f"Generador a perder: {gen.loc_name} ({p_pre:.1f} MW)")

        # evento de desconexión en el set de eventos del sandbox
        evt_folder = app.GetFromStudyCase("IntEvt")
        for e in evt_folder.GetContents():  # limpiar eventos heredados de BASE
            e.Delete()
        evt = evt_folder.CreateObject("EvtSwitch", "perdida_PC2")
        evt.SetAttribute("time", 1.0)
        evt.SetAttribute("p_target", gen)
        try:
            evt.SetAttribute("i_switch", 0)  # abrir
        except Exception:
            warnings.append("EvtSwitch: no se pudo fijar i_switch (default abrir)")

        # resultados y variables monitoreadas
        res = sbx.CreateObject("ElmRes", "res_rms_edac")

        def monitorear(elem, variables):
            mon = res.CreateObject("IntMon", elem.loc_name[:40])
            mon.SetAttribute("obj_id", elem)
            mon.SetAttribute("vars", variables)

        barras = []
        vistos = set()
        cupo = dict(MAX_BARRAS_POR_NIVEL)
        for term in sorted(app.GetCalcRelevantObjects("*.ElmTerm"),
                           key=lambda t: (-float(attr(t, "uknom", 0) or 0), t.loc_name)):
            kv = float(attr(term, "uknom", 0) or 0)
            if kv not in cupo or cupo[kv] <= 0 or attr(term, "outserv", 0) == 1:
                continue
            if term.loc_name in vistos or attr(term, "iUsage", 0) != 0:
                continue  # iUsage 0 = busbar (evita nodos internos/junction)
            vistos.add(term.loc_name)
            barras.append(term)
            cupo[kv] -= 1
        for b in barras:
            monitorear(b, ["m:fehz"])
        print(f"Barras monitoreadas ({len(barras)}):", [b.loc_name for b in barras])

        maquinas = [g for g in app.GetCalcRelevantObjects("*.ElmSym")
                    if attr(g, "outserv", 0) == 0]
        for g in maquinas:
            monitorear(g, ["s:speed"])

        cargas = cargas_edac(app)
        print(f"Cargas EDAC monitoreadas: {len(cargas)}")
        for c in cargas:
            monitorear(c, ["m:Psum:bus1"])

        # condiciones iniciales + simulación
        inc = app.GetFromStudyCase("ComInc")
        inc.SetAttribute("iopt_sim", "rms")
        inc.SetAttribute("iopt_show", 0)
        try:
            inc.SetAttribute("p_resvar", res)
        except Exception:
            warnings.append("ComInc: no se pudo asignar p_resvar")
        try:
            inc.SetAttribute("dtgrd", args.paso)
        except Exception:
            warnings.append("ComInc: no se pudo fijar dtgrd")
        try:
            inc.SetAttribute("p_event", evt_folder)
        except Exception:
            pass

        try:
            app.ClearOutputWindow()
        except Exception:
            pass

        err = inc.Execute()
        if err:
            raise RuntimeError(f"ComInc devolvió {err} — no hay condiciones iniciales")
        sim = app.GetFromStudyCase("ComSim")
        sim.SetAttribute("tstop", args.tstop)
        print("Corriendo RMS...")
        err = sim.Execute()
        if err:
            warnings.append(f"ComSim devolvió {err}")
        print("RMS terminado")

        # mensajes del output window (best effort)
        try:
            ow = app.GetOutputWindow()
            contenido = ow.GetContent()
            (out / "rms_edac_output.txt").write_text(
                "\n".join(str(x) for x in contenido), encoding="utf-8")
        except Exception as e:
            warnings.append(f"output window no accesible: {e}")

        # ------------------- exportar ElmRes -------------------
        res.Load()
        n_filas = res.GetNumberOfRows()
        print(f"Filas de resultados: {n_filas}")

        columnas = [("t", None, "b:tnow")]
        for b in barras:
            columnas.append((f"f_{b.loc_name}", b, "m:fehz"))
        for g in maquinas:
            columnas.append((f"speed_{g.loc_name}", g, "s:speed"))
        for c in cargas:
            columnas.append((f"P_{c.loc_name}", c, "m:Psum:bus1"))

        indices = []
        for nombre_col, elem, var in columnas:
            try:
                if elem is None:
                    indices.append((nombre_col, -1))
                else:
                    idx = res.FindColumn(elem, var)
                    indices.append((nombre_col, idx))
                    if idx < 0:
                        warnings.append(f"columna no encontrada: {nombre_col} {var}")
            except Exception as e:
                indices.append((nombre_col, -2))
                warnings.append(f"FindColumn {nombre_col}: {e}")

        with open(out / "rms_edac_series.csv", "w", newline="",
                  encoding="utf-8-sig") as f:
            w = csv.writer(f)
            w.writerow([n for n, _ in indices])
            for i in range(n_filas):
                fila = []
                for nombre_col, idx in indices:
                    try:
                        if idx == -1:
                            fila.append(res.GetValue(i, -1)[1])
                        elif idx >= 0:
                            fila.append(res.GetValue(i, idx)[1])
                        else:
                            fila.append("")
                    except Exception:
                        fila.append("")
                w.writerow(fila)
        res.Release()

        # ------------------- disparos por carga -------------------
        # una carga deslastrada: P cae a ~0 y no vuelve
        import io

        with open(out / "rms_edac_series.csv", encoding="utf-8-sig") as f:
            filas = list(csv.reader(f))
        cab = filas[0]
        datos = filas[1:]
        t_idx = cab.index("t")
        disparos = []
        for j, col in enumerate(cab):
            if not col.startswith("P_"):
                continue
            serie = []
            for r in datos:
                try:
                    serie.append((float(r[t_idx]), float(r[j])))
                except Exception:
                    continue
            if not serie:
                continue
            p0 = serie[0][1]
            t_trip = ""
            for t, p in serie:
                if abs(p) < max(0.02 * abs(p0), 1e-3) and abs(p0) > 1e-3:
                    t_trip = t
                    break
            disparos.append({"carga": col[2:], "P_inicial_MW": round(p0, 3),
                             "t_disparo_s": t_trip,
                             "P_final_MW": round(serie[-1][1], 3)})
        escritor = csv.DictWriter(
            open(out / "rms_edac_disparos.csv", "w", newline="", encoding="utf-8-sig"),
            fieldnames=["carga", "P_inicial_MW", "t_disparo_s", "P_final_MW"])
        escritor.writeheader()
        escritor.writerows(disparos)
        n_trip = sum(1 for d in disparos if d["t_disparo_s"] != "")
        mw_trip = sum(d["P_inicial_MW"] for d in disparos if d["t_disparo_s"] != "")
        print(f"Cargas deslastradas: {n_trip} ({mw_trip:.1f} MW)")

        meta = {"proyecto": PROYECTO, "escenario": args.escenario,
                "evento": f"pérdida {GEN_PERDIDO} ({p_pre:.1f} MW) a t=1 s",
                "tstop_s": args.tstop, "paso_s": args.paso,
                "study_case_sandbox": sbx.loc_name,
                "n_cargas_edac_monitoreadas": len(cargas),
                "n_deslastradas": n_trip, "MW_deslastrados": round(mw_trip, 3),
                "fecha": datetime.now().isoformat()}
        (out / "_META.json").write_text(
            json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    finally:
        # limpiar sandbox y reactivar BASE
        try:
            base_case.Activate()
            sbx.Delete()
            print("Sandbox eliminado, BASE reactivado")
        except Exception as e:
            warnings.append(f"limpieza del sandbox: {e}")
        if warnings:
            (out / "_WARNINGS.txt").write_text("\n".join(warnings), encoding="utf-8")

    print(f"Salida en {out}")


if __name__ == "__main__":
    sys.exit(main())
