# -*- coding: utf-8 -*-
"""Extractor para la VM con DIgSILENT PowerFactory 2024 (SOLO LECTURA).

Misión y prioridades: ver las reglas del proyecto (raíz del repo), sección VM.
Bloques y columnas exactas: docs/EXTRACCION_DINAMICA_DIGSILENT.md.

Prioridad 1 — Bloque I: punto de operación exacto del escenario (P20):
    escenario_<ESC>_cargas.csv / _generacion.csv / _taps.csv + comldf_opciones.json
Prioridad 2 — EDAC en detalle:
    edac_detalle.csv        una fila por etapa RelFrq, con interruptor, objeto
                            disparado y MW aguas abajo en el escenario base
    edac_aguas_abajo.csv    formato largo: etapa → cada elemento desconectado
    edac_mw_por_escenario.csv  MW deslastrable por etapa en P01..P24
    escenarios_demanda.csv  demanda total por escenario (control)

Uso (en la VM, con el Python del PowerFactory):
    python scripts/pf/extract_vm.py --escenario P20 --salida data/raw

Patrón de conexión tomado del Feasibility-Study (pf_worker/connect.py):
una sola instancia de PowerFactory por proceso; no thread-safe.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import defaultdict, deque
from datetime import datetime
from pathlib import Path

PF_PYD = r"C:\Program Files\DIgSILENT\PowerFactory 2024\Python\3.9"
PROYECTO = "PDD 30-09-2025"
ESCENARIOS_TODOS = ["P%02d" % i for i in range(1, 25)]

# clases que forman aristas del grafo topológico (conectan ≥2 terminales)
CLASES_RAMA = {"ElmLne", "ElmTr2", "ElmTr3", "ElmTr4", "ElmCoup", "ElmSind",
               "ElmZpu", "ElmBranch", "ElmSercap", "ElmScap", "ElmVscmono", "ElmVsc"}
# clases "hoja" (dispositivos colgados de un terminal)
CLASES_DISPOSITIVO = {"ElmLod", "ElmLodlv", "ElmSym", "ElmGenstat", "ElmAsm",
                      "ElmShnt", "ElmSvs", "ElmVac", "ElmXnet", "ElmPvsys"}


def conectar():
    sys.path.insert(0, PF_PYD)
    import powerfactory  # requiere el pyd del PF 2024

    app = powerfactory.GetApplication()
    if app is None:
        raise RuntimeError("No se pudo obtener la aplicación PowerFactory")
    app.SetWriteCacheEnabled(0)
    return app


def activar_proyecto(app):
    err = app.ActivateProject(PROYECTO)
    if err:
        raise RuntimeError(f"No se pudo activar el proyecto {PROYECTO}")


def activar_escenario(app, escenario: str):
    escenarios = app.GetProjectFolder("scen").GetContents("*.IntScenario")
    for sc in escenarios:
        if sc.loc_name.strip().upper() == escenario.upper():
            sc.Activate()
            return sc
    raise RuntimeError(f"Escenario {escenario} no encontrado")


def attr(obj, nombre, default=""):
    try:
        v = obj.GetAttribute(nombre)
        return default if v is None else v
    except Exception:
        return default


def nombre(obj):
    return obj.loc_name if obj is not None else ""


def escribir_csv(path: Path, filas: list[dict]):
    if not filas:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=list(filas[0].keys()))
        w.writeheader()
        w.writerows(filas)


# --------------------------- Prioridad 1: Bloque I ---------------------------

def bloque_i(app, out: Path, escenario: str, warnings: list[str]):
    """Punto de operación exacto del escenario activo + opciones del ComLdf."""
    cargas = []
    for lod in app.GetCalcRelevantObjects("*.ElmLod"):
        cargas.append({
            "for_name": attr(lod, "for_name"),
            "loc_name": lod.loc_name,
            "ruta": lod.GetFullName(),
            "P_MW": attr(lod, "plini"),
            "Q_Mvar": attr(lod, "qlini"),
            "escala": attr(lod, "scale0"),
            "outserv": attr(lod, "outserv"),
        })
    escribir_csv(out / f"escenario_{escenario}_cargas.csv", cargas)

    gens = []
    for clase, tag in (("*.ElmSym", "sym"), ("*.ElmGenstat", "genstat")):
        for g in app.GetCalcRelevantObjects(clase):
            cub = attr(g, "bus1", None)
            barra = attr(cub, "cterm", None) if cub not in (None, "") else None
            gens.append({
                "clase": tag,
                "for_name": attr(g, "for_name"),
                "loc_name": g.loc_name,
                "barra_for_name": attr(barra, "for_name") if barra else "",
                "barra_loc_name": nombre(barra),
                "P_desp_MW": attr(g, "pgini"),
                "Q_desp_Mvar": attr(g, "qgini"),
                "U_consigna_pu": attr(g, "usetp"),
                "modo_ctrl_av": attr(g, "av_mode"),
                "num_unidades": attr(g, "ngnum"),
                "outserv": attr(g, "outserv"),
                "ref_slack": attr(g, "ip_ctrl"),
            })
    escribir_csv(out / f"escenario_{escenario}_generacion.csv", gens)

    taps = []
    for clase in ("*.ElmTr2", "*.ElmTr3"):
        for t in app.GetCalcRelevantObjects(clase):
            fila = {
                "for_name": attr(t, "for_name"),
                "loc_name": t.loc_name,
                "ruta": t.GetFullName(),
                "clase": clase[2:],
                "tap_actual": attr(t, "nntap"),
                "outserv": attr(t, "outserv"),
            }
            if clase == "*.ElmTr3":
                # posiciones por devanado del tridevanado
                for lado, a in (("hv", "n3tap_h"), ("mv", "n3tap_m"), ("lv", "n3tap_l")):
                    fila[f"tap_{lado}"] = attr(t, a)
            taps.append(fila)
    # ElmTr3 añade columnas extra → normalizar claves
    claves = []
    for f in taps:
        for k in f:
            if k not in claves:
                claves.append(k)
    taps = [{k: f.get(k, "") for k in claves} for f in taps]
    escribir_csv(out / f"escenario_{escenario}_taps.csv", taps)

    # opciones del ComLdf del study case activo (¡clave para la Fase 2!)
    ldf = app.GetFromStudyCase("ComLdf")
    opciones = {"_study_case": nombre(app.GetActiveStudyCase()),
                "_comldf_ruta": ldf.GetFullName()}
    for campo in (
            # básicos
            "iopt_net", "iopt_show", "iopt_check",
            # dependencia de tensión de cargas / escalado
            "iopt_pq", "iopt_fls", "iScaleLd", "iopt_sca",
            # taps y shunts automáticos
            "iopt_at", "iopt_asht", "iPST_at",
            # límites de reactiva / activa
            "iopt_lim", "iopt_plim", "iopt_qlim", "iopt_lim_scale",
            # balance / slack distribuido
            "iPbalancing", "iopt_apdist", "iopt_bal", "iopt_spar",
            # control de tensión / estaciones
            "iopt_tem", "iopt_pc", "iopt_sim", "iopt_prot",
            # iteración
            "iopt_it", "itrlx", "ittr", "erreq", "errlf", "nsteps"):
        v = attr(ldf, campo, default=None)
        if hasattr(v, "loc_name"):
            v = v.GetFullName()
        opciones[campo] = v
    (out / "comldf_opciones.json").write_text(
        json.dumps(opciones, indent=2, default=str, ensure_ascii=False),
        encoding="utf-8")
    n_falt = sum(1 for k, v in opciones.items() if v is None)
    if n_falt:
        warnings.append(f"comldf: {n_falt} atributos no existentes (None) — revisar nombres")


# ------------------------ Prioridad 2: EDAC en detalle ------------------------

def cubiculo_cerrado(cub):
    for s in cub.GetContents("*.StaSwitch"):
        if attr(s, "on_off", 1) == 0:
            return False
    return True


def construir_grafo(app, warnings: list[str]):
    """Grafo de conectividad: nodos = ElmTerm, aristas = ramas en servicio con
    cubículos cerrados. Devuelve (adyacencia, term_de_dispositivo, rama_terms)."""
    aristas = defaultdict(list)      # rama -> [(term, cerrado)]
    dispositivos = defaultdict(list)  # dispositivo -> [(term, cerrado)]
    for term in app.GetCalcRelevantObjects("*.ElmTerm"):
        for cub in term.GetContents("*.StaCubic"):
            oid = attr(cub, "obj_id", None)
            if oid in (None, ""):
                continue
            cl = oid.GetClassName()
            cerrado = cubiculo_cerrado(cub)
            if cl in CLASES_RAMA:
                aristas[oid].append((term, cerrado))
            elif cl in CLASES_DISPOSITIVO:
                dispositivos[oid].append((term, cerrado))

    ady = defaultdict(set)  # term -> set(term)
    rama_terms = {}         # rama -> [terms] (independiente del estado)
    for rama, conexiones in aristas.items():
        terms = [t for t, _ in conexiones]
        rama_terms[rama] = terms
        if attr(rama, "outserv", 0) == 1:
            continue
        if rama.GetClassName() == "ElmCoup" and attr(rama, "on_off", 1) == 0:
            continue
        if any(not c for _, c in conexiones):
            continue
        for i, ta in enumerate(terms):
            for tb in terms[i + 1:]:
                ady[ta].add(tb)
                ady[tb].add(ta)
    return ady, dispositivos, rama_terms


def bfs(ady, inicio, excluir_pares=frozenset()):
    """BFS sobre terminales; excluir_pares = aristas (a,b) suprimidas."""
    visto = {inicio}
    cola = deque([inicio])
    while cola:
        t = cola.popleft()
        for v in ady[t]:
            if v in visto:
                continue
            if (t, v) in excluir_pares or (v, t) in excluir_pares:
                continue
            visto.add(v)
            cola.append(v)
    return visto


def raiz_relay(rel):
    """Sube por la cadena de padres hasta el cubículo (relés anidados)."""
    cadena = [rel]
    p = rel.GetParent()
    while p is not None and p.GetClassName() == "ElmRelay":
        cadena.append(p)
        p = p.GetParent()
    cub = p if (p is not None and p.GetClassName() == "StaCubic") else None
    return cadena[-1], cub


def resolver_aguas_abajo(objeto, ady, dispositivos, rama_terms, term_slack):
    """Qué queda desconectado al abrir `objeto`.

    Devuelve (lista_dispositivos, lista_ramas, es_malla):
    - dispositivo ElmLod/ElmSym/...: él mismo
    - rama: componentes que quedan sin camino al slack al retirar la rama
    """
    cl = objeto.GetClassName()
    if cl in CLASES_DISPOSITIVO:
        return [objeto], [], False
    terms = rama_terms.get(objeto)
    if not terms:
        return [], [], False
    # suprimir las aristas de esta rama y ver qué pierde el camino al slack
    pares = set()
    for i, ta in enumerate(terms):
        for tb in terms[i + 1:]:
            pares.add((ta, tb))
    alcanzable = bfs(ady, term_slack, excluir_pares=frozenset(pares))
    perdidos = set()
    for t in terms:
        if t in alcanzable or t in perdidos:
            continue
        if t not in ady and t != term_slack:
            perdidos.add(t)
            continue
        perdidos |= bfs(ady, t, excluir_pares=frozenset(pares))
    perdidos -= alcanzable
    if not perdidos:
        return [], [], True  # malla: abrir la rama no aísla nada
    dispositivos_perdidos = []
    for disp, conex in dispositivos.items():
        if any(t in perdidos for t, cerrado in conex if cerrado):
            dispositivos_perdidos.append(disp)
    ramas_perdidas = [r for r, ts in rama_terms.items()
                      if r is not objeto and ts and all(t in perdidos for t in ts)]
    return dispositivos_perdidos, ramas_perdidas, False


def term_del_slack(app):
    for g in app.GetCalcRelevantObjects("*.ElmSym"):
        if attr(g, "ip_ctrl") == 1 and attr(g, "outserv", 0) == 0:
            cub = attr(g, "bus1", None)
            if cub not in (None, ""):
                return attr(cub, "cterm", None), g.loc_name
    raise RuntimeError("No se encontró la máquina slack (ip_ctrl=1)")


def edac_detalle(app, out: Path, escenario_base: str, escenarios: list[str],
                 warnings: list[str]):
    print("  construyendo grafo de conectividad...")
    ady, dispositivos, rama_terms = construir_grafo(app, warnings)
    term_slack, slack_name = term_del_slack(app)
    if term_slack in (None, ""):
        raise RuntimeError("Slack sin terminal")
    print(f"  slack: {slack_name} | terminales en grafo: {len(ady)}")

    relays = [r for r in app.GetCalcRelevantObjects("*.ElmRelay")
              if r.GetContents("*.RelFrq")]
    print(f"  relés con RelFrq: {len(relays)}")

    filas = []
    filas_largo = []
    cache_aguas_abajo = {}  # objeto -> (disps, ramas, malla)
    etapa_cargas = {}       # (relay_ruta, etapa) -> [ElmLod aguas abajo]

    for rel in relays:
        rel_root, cub = raiz_relay(rel)
        objeto = attr(cub, "obj_id", None) if cub is not None else None
        term = attr(cub, "cterm", None) if cub is not None else None
        interruptores = ";".join(s.loc_name for s in cub.GetContents("*.StaSwitch")) \
            if cub is not None else ""
        rel_out = attr(rel, "outserv", 0)
        root_out = attr(rel_root, "outserv", 0)

        if objeto is not None and objeto != "":
            key = objeto.GetFullName()
            if key not in cache_aguas_abajo:
                cache_aguas_abajo[key] = resolver_aguas_abajo(
                    objeto, ady, dispositivos, rama_terms, term_slack)
            disps, ramas, malla = cache_aguas_abajo[key]
        else:
            disps, ramas, malla = [], [], False
            warnings.append(f"edac: cubículo sin obj_id — relay {rel.GetFullName()}")

        cargas_ab = [d for d in disps if d.GetClassName() in ("ElmLod", "ElmLodlv")
                     and attr(d, "outserv", 0) == 0]
        gens_ab = [d for d in disps if d.GetClassName() in ("ElmSym", "ElmGenstat", "ElmAsm")
                   and attr(d, "outserv", 0) == 0]
        mw_cargas = sum(float(attr(d, "plini", 0) or 0) for d in cargas_ab)
        mvar_cargas = sum(float(attr(d, "qlini", 0) or 0) for d in cargas_ab)
        mw_gens = sum(float(attr(d, "pgini", 0) or 0) * max(int(attr(d, "ngnum", 1) or 1), 1)
                      for d in gens_ab)

        for frq in rel.GetContents("*.RelFrq"):
            frq_out = attr(frq, "outserv", 0)
            activa = int(rel_out == 0 and root_out == 0 and frq_out == 0)
            fila = {
                "relay_for_name": attr(rel_root, "for_name"),
                "relay_root": rel_root.loc_name,
                "relay_ruta": rel_root.GetFullName(),
                "subrelay": rel.loc_name if rel is not rel_root else "",
                "etapa": frq.loc_name,
                "f_arranque_hz": attr(frq, "Fset"),
                "dfdt_hz_s": attr(frq, "dFset"),
                "retardo_s": attr(frq, "Tdel"),
                "etapa_outserv": frq_out,
                "subrelay_outserv": rel_out if rel is not rel_root else "",
                "relay_outserv": root_out,
                "activa_efectiva": activa,
                "terminal": nombre(term) if term not in (None, "") else "",
                "terminal_for_name": attr(term, "for_name") if term not in (None, "") else "",
                "terminal_kV": attr(term, "uknom") if term not in (None, "") else "",
                "cubiculo": nombre(cub) if cub is not None else "",
                "interruptor": interruptores,
                "objeto_disparado": nombre(objeto) if objeto not in (None, "") else "",
                "objeto_clase": objeto.GetClassName() if objeto not in (None, "") else "",
                "objeto_for_name": attr(objeto, "for_name") if objeto not in (None, "") else "",
                "es_malla": int(malla),
                "n_cargas_aguas_abajo": len(cargas_ab),
                "MW_deslastrados": round(mw_cargas, 3),
                "Mvar_deslastrados": round(mvar_cargas, 3),
                "n_gens_aguas_abajo": len(gens_ab),
                "MW_gen_desconectados": round(mw_gens, 3),
            }
            filas.append(fila)
            etapa_cargas[(rel_root.GetFullName(), rel.loc_name, frq.loc_name)] = cargas_ab

            for d in disps:
                filas_largo.append({
                    "relay_root": rel_root.loc_name,
                    "relay_ruta": rel_root.GetFullName(),
                    "subrelay": rel.loc_name if rel is not rel_root else "",
                    "etapa": frq.loc_name,
                    "f_arranque_hz": attr(frq, "Fset"),
                    "activa_efectiva": activa,
                    "elemento_clase": d.GetClassName(),
                    "elemento_for_name": attr(d, "for_name"),
                    "elemento_loc_name": d.loc_name,
                    "elemento_ruta": d.GetFullName(),
                    "P_MW": attr(d, "plini") if d.GetClassName() in ("ElmLod", "ElmLodlv")
                            else attr(d, "pgini"),
                    "outserv": attr(d, "outserv"),
                })
            for r in ramas:
                filas_largo.append({
                    "relay_root": rel_root.loc_name,
                    "relay_ruta": rel_root.GetFullName(),
                    "subrelay": rel.loc_name if rel is not rel_root else "",
                    "etapa": frq.loc_name,
                    "f_arranque_hz": attr(frq, "Fset"),
                    "activa_efectiva": activa,
                    "elemento_clase": r.GetClassName(),
                    "elemento_for_name": attr(r, "for_name"),
                    "elemento_loc_name": r.loc_name,
                    "elemento_ruta": r.GetFullName(),
                    "P_MW": "",
                    "outserv": attr(r, "outserv"),
                })

    escribir_csv(out / "edac_detalle.csv", filas)
    escribir_csv(out / "edac_aguas_abajo.csv", filas_largo)
    print(f"  edac_detalle: {len(filas)} etapas | aguas_abajo: {len(filas_largo)} filas")

    # ---- MW deslastrable por etapa y escenario (P01..P24) ----
    # nota: los conjuntos aguas abajo se resuelven con la topología del escenario
    # base; entre escenarios solo se re-lee P/outserv de cada carga.
    filas_esc = []
    filas_dem = []
    for esc in escenarios:
        try:
            activar_escenario(app, esc)
        except Exception as e:
            warnings.append(f"escenario {esc}: no se pudo activar ({e})")
            continue
        p_por_carga = {}
        total = 0.0
        for lod in app.GetCalcRelevantObjects("*.ElmLod"):
            p = float(attr(lod, "plini", 0) or 0)
            fuera = attr(lod, "outserv", 0)
            p_por_carga[lod.GetFullName()] = (p, fuera)
            if fuera == 0:
                total += p
        filas_dem.append({"escenario": esc, "demanda_total_MW": round(total, 3)})
        for (ruta_rel, sub, etapa), cargas_ab in etapa_cargas.items():
            mw = sum(p for p, fuera in
                     (p_por_carga.get(c.GetFullName(), (0.0, 1)) for c in cargas_ab)
                     if fuera == 0)
            filas_esc.append({
                "relay_ruta": ruta_rel, "subrelay": sub, "etapa": etapa,
                "escenario": esc, "MW_deslastrados": round(mw, 3),
            })
        print(f"  {esc}: demanda {total:,.1f} MW")
    escribir_csv(out / "edac_mw_por_escenario.csv", filas_esc)
    escribir_csv(out / "escenarios_demanda.csv", filas_dem)
    warnings.append("edac_mw_por_escenario: conjuntos aguas abajo resueltos con la "
                    f"topología de {escenario_base}; entre escenarios solo cambia P/outserv")
    # volver al escenario base
    activar_escenario(app, escenario_base)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--escenario", default="P20")
    ap.add_argument("--salida", default="data/raw")
    ap.add_argument("--sin-escenarios", action="store_true",
                    help="no recorrer P01..P24 para los MW del EDAC")
    args = ap.parse_args()

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out = Path(args.salida) / f"salida_bloqueI_edac_{stamp}"
    out.mkdir(parents=True, exist_ok=True)
    warnings: list[str] = []

    app = conectar()
    activar_proyecto(app)
    activar_escenario(app, args.escenario)
    print(f"Proyecto {PROYECTO} | escenario {args.escenario} | "
          f"study case {nombre(app.GetActiveStudyCase())}")

    print("Bloque I (punto de operación)...")
    bloque_i(app, out, args.escenario, warnings)

    print("EDAC en detalle...")
    escenarios = [] if args.sin_escenarios else ESCENARIOS_TODOS
    edac_detalle(app, out, args.escenario, escenarios, warnings)

    conteos = {c: len(app.GetCalcRelevantObjects("*." + c))
               for c in ("ElmLod", "ElmSym", "ElmGenstat", "ElmTr2", "ElmTr3",
                         "ElmLne", "ElmTerm", "ElmRelay")}
    meta = {"proyecto": PROYECTO, "escenario": args.escenario,
            "study_case": nombre(app.GetActiveStudyCase()),
            "fecha": datetime.now().isoformat(),
            "conteos": conteos,
            "archivos": sorted(p.name for p in out.iterdir())}
    (out / "_META.json").write_text(
        json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    if warnings:
        (out / "_WARNINGS.txt").write_text("\n".join(warnings), encoding="utf-8")
    print(f"Extracción en {out}")


if __name__ == "__main__":
    sys.exit(main())
