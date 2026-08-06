# -*- coding: utf-8 -*-
"""Extractor Ronda 2 para la VM con DIgSILENT PowerFactory 2024 (SOLO LECTURA).

Especificación: EXTRACCION_VM_RONDA2.md (raíz del repo).
Complementa la Ronda 1 (`scripts/pf/extract_vm.py`, Bloque I + EDAC).

Bloques (`--solo` para correr uno):
  shunts   P1+P2 → data/raw/salida_shunts_svc_<stamp>/
           escenario_P20_shunts.csv, _svc.csv, _stactrl.csv, _qcap.csv,
           qcap_curvas.csv  (flujo de carga en sandbox para Q real)
  op       P3    → data/raw/salida_op_P01_P24_<stamp>/
           op_cargas/op_generacion/op_taps/op_shunts_P01_P24.csv + resumen
  agc      P4+P5 → data/raw/salida_agc_hidro_<stamp>/
           agc_participacion.csv, hidro_parametros.csv, gov_parametros.csv
  frt      P6    → data/raw/salida_oarray_frt_<stamp>/
           oarray_frt_completo.csv

Reglas: solo lectura; sandbox para el flujo (se borra al final); escenario
restaurado a P20 siempre; GetAttribute en try/except.

Uso:  python scripts/pf/extract_vm_r2.py [--solo shunts|op|agc|frt]
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

# modelos DSL que delatan una máquina hidráulica
CLAVES_HIDRO = ("HYGOV", "HYDRO", "FRANCIS", "NEYPRIC", "KAPLAN", "PELTON")
# nombres candidatos del estatismo permanente en los gobernadores
CLAVES_DROOP = ("R", "r", "bp", "Rperm", "droop", "Droop", "sigma", "Kdroop")


def conectar():
    sys.path.insert(0, PF_PYD)
    import powerfactory

    app = powerfactory.GetApplication()
    if app is None:
        raise RuntimeError("No se pudo obtener PowerFactory")
    app.SetWriteCacheEnabled(0)
    return app


def attr(obj, nombre, default=""):
    """GetAttribute robusto (regla 3 de las reglas del proyecto)."""
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


def barra_de(obj, campo="bus1"):
    cub = attr(obj, campo, None)
    if cub in (None, ""):
        return None
    return attr(cub, "cterm", None) or None


def escribir_csv(path: Path, filas):
    if not filas:
        return
    claves = []
    for f in filas:
        for k in f:
            if k not in claves:
                claves.append(k)
    filas = [{k: f.get(k, "") for k in claves} for f in filas]
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=claves)
        w.writeheader()
        w.writerows(filas)


def cerrar(out: Path, meta: dict, warnings):
    meta["archivos"] = sorted(p.name for p in out.iterdir())
    (out / "_META.json").write_text(
        json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    if warnings:
        (out / "_WARNINGS.txt").write_text("\n".join(warnings), encoding="utf-8")


# ============ P1 + P2 — shunts, SVC, station controllers, curvas Q ============

def bloque_shunts(app, raiz: Path, stamp: str):
    out = raiz / ("salida_shunts_svc_%s" % stamp)
    out.mkdir(parents=True, exist_ok=True)
    warnings = []

    # --- flujo de carga en sandbox (para Q real de shunts/SVC/generadores) ---
    base_case = app.GetActiveStudyCase()
    sbx = base_case.GetParent().AddCopy(base_case, "SBX_R2_%s" % stamp)
    q_shunt, q_svc, q_gen = {}, {}, {}
    tensiones = []
    ldf_err = None
    try:
        sbx.Activate()
        ldf = app.GetFromStudyCase("ComLdf")
        ldf_err = ldf.Execute()
        if ldf_err:
            warnings.append("ComLdf devolvió %s — las columnas Q_actual quedan vacías"
                            % ldf_err)
        else:
            # tensiones resueltas: referencia directa para comparar con la Fase 2
            for t in app.GetCalcRelevantObjects("*.ElmTerm"):
                if attr(t, "outserv", 0) == 1:
                    continue
                v_pu = attr(t, "m:u")
                tensiones.append({
                    "for_name": attr(t, "for_name"),
                    "loc_name": t.loc_name,
                    "ruta": t.GetFullName(),
                    "kV_nominal": attr(t, "uknom"),
                    "V_pu": v_pu,
                    "angulo_deg": attr(t, "m:phiu"),
                    "V_kV": attr(t, "m:U"),
                    # V=0 → barra en isla sin energizar (no comparable con Sienna)
                    "energizada": int(isinstance(v_pu, float) and v_pu > 0.01),
                })
            for o in app.GetCalcRelevantObjects("*.ElmShnt"):
                q_shunt[o.GetFullName()] = attr(o, "m:Q:bus1")
            for o in app.GetCalcRelevantObjects("*.ElmSvs"):
                q_svc[o.GetFullName()] = attr(o, "m:Q:bus1")
            for cl in ("*.ElmSym", "*.ElmGenstat"):
                for o in app.GetCalcRelevantObjects(cl):
                    q_gen[o.GetFullName()] = (attr(o, "m:Q:bus1"), attr(o, "m:P:bus1"))
    finally:
        base_case.Activate()
        try:
            sbx.Delete()
        except Exception as e:
            warnings.append("no se pudo borrar el sandbox: %s" % e)

    # --- shunts ---
    filas = []
    for o in app.GetCalcRelevantObjects("*.ElmShnt"):
        b = barra_de(o)
        ncapa = attr(o, "ncapa", "")
        qcapn = attr(o, "qcapn", "")
        filas.append({
            "for_name": attr(o, "for_name"),
            "loc_name": o.loc_name,
            "ruta": o.GetFullName(),
            "barra_for_name": attr(b, "for_name") if b else "",
            "barra_loc_name": nombre(b),
            "barra_kV": attr(b, "uknom") if b else "",
            "shtype": attr(o, "shtype"),          # 1=R,2=C,3=L,4=RL...
            "ctech": attr(o, "ctech"),
            "ncapa": ncapa,                        # pasos EN SERVICIO en P20
            "ncapx": attr(o, "ncapx"),             # pasos máximos
            "qcapn_Mvar_paso": qcapn,
            "qtotn_Mvar": attr(o, "qtotn"),
            "Q_nominal_en_servicio_Mvar": (
                round(float(ncapa) * float(qcapn), 4)
                if ncapa not in ("", None) and qcapn not in ("", None) else ""),
            "Q_actual_Mvar": q_shunt.get(o.GetFullName(), ""),
            "ushnm_kV": attr(o, "ushnm"),
            "iswitch": attr(o, "iswitch"),         # conmutable
            "nodo_control": nombre(attr(o, "cpCtrlNode", None)),
            "outserv": attr(o, "outserv"),
        })
    escribir_csv(out / "escenario_P20_tensiones_flujo.csv", tensiones)
    if tensiones:
        n_ener = sum(t["energizada"] for t in tensiones)
        v69 = [float(t["V_pu"]) for t in tensiones
               if t["kV_nominal"] == 69.0 and t["energizada"]]
        if v69:
            print("  tensiones: %d barras (%d energizadas) | 69 kV: Vmin=%.4f "
                  "Vmedia=%.4f Vmax=%.4f"
                  % (len(tensiones), n_ener, min(v69), sum(v69) / len(v69), max(v69)))
    escribir_csv(out / "escenario_P20_shunts.csv", filas)
    n_serv = [f for f in filas if f["outserv"] == 0]
    q_cap = sum(float(f["Q_actual_Mvar"] or 0) for f in n_serv)
    print("  shunts: %d (%d en servicio) | ΣQ_actual = %.1f Mvar"
          % (len(filas), len(n_serv), q_cap))

    # --- SVC ---
    filas_svc = []
    for o in app.GetCalcRelevantObjects("*.ElmSvs"):
        b = barra_de(o)
        filas_svc.append({
            "for_name": attr(o, "for_name"),
            "loc_name": o.loc_name,
            "ruta": o.GetFullName(),
            "barra_for_name": attr(b, "for_name") if b else "",
            "barra_loc_name": nombre(b),
            "qmin_Mvar": attr(o, "qmin"),
            "qmax_Mvar": attr(o, "qmax"),
            "usetp_pu": attr(o, "usetp"),
            "qsetp_Mvar": attr(o, "qsetp"),
            "modo_ctrl_i_ctrl": attr(o, "i_ctrl"),
            "Q_actual_Mvar": q_svc.get(o.GetFullName(), ""),
            "outserv": attr(o, "outserv"),
        })
    escribir_csv(out / "escenario_P20_svc.csv", filas_svc)
    print("  SVC: %d" % len(filas_svc))

    # --- station controllers ---
    filas_st = []
    for o in app.GetCalcRelevantObjects("*.ElmStactrl"):
        rem = attr(o, "rembar", None)
        # la lista psym puede traer huecos (None) en slots sin máquina asignada
        maquinas = [m for m in (attr(o, "psym", []) or []) if m is not None]
        filas_st.append({
            "for_name": attr(o, "for_name"),
            "loc_name": o.loc_name,
            "ruta": o.GetFullName(),
            "nudo_piloto_loc_name": nombre(rem),
            "nudo_piloto_for_name": attr(rem, "for_name") if rem else "",
            "nudo_piloto_kV": attr(rem, "uknom") if rem else "",
            "usetp_pu": attr(o, "usetp"),
            "qsetp_Mvar": attr(o, "qsetp"),
            "i_ctrl": attr(o, "i_ctrl"),
            "imode": attr(o, "imode"),
            "uset_mode": attr(o, "uset_mode"),
            "i_droop": attr(o, "i_droop"),
            "ddroop": attr(o, "ddroop"),
            "n_maquinas": len(maquinas),
            "maquinas_for_name": ";".join(attr(m, "for_name") or nombre(m)
                                          for m in maquinas),
            "outserv": attr(o, "outserv"),
        })
    escribir_csv(out / "escenario_P20_stactrl.csv", filas_st)
    print("  station controllers: %d" % len(filas_st))

    # --- curvas de capacidad Q ---
    filas_q, filas_curva = [], []
    curvas_vistas = set()
    for cl, tag in (("*.ElmSym", "sym"), ("*.ElmGenstat", "genstat")):
        for g in app.GetCalcRelevantObjects(cl):
            b = barra_de(g)
            typ = attr(g, "typ_id", None)
            qlim = attr(g, "pQlimType", None)
            q_act, p_act = q_gen.get(g.GetFullName(), ("", ""))
            filas_q.append({
                "clase": tag,
                "for_name": attr(g, "for_name"),
                "loc_name": g.loc_name,
                "barra_for_name": attr(b, "for_name") if b else "",
                # ElmGenstat trae sgn/cosn en el elemento; ElmSym en su TypSym
                "sgn_MVA": attr(g, "sgn") or (attr(typ, "sgn") if typ else ""),
                "cosn": attr(g, "cosn") or (attr(typ, "cosn") if typ else ""),
                "P_desp_MW": attr(g, "pgini"),
                "Q_desp_Mvar": attr(g, "qgini"),
                "P_actual_MW": p_act,
                "Q_actual_Mvar": q_act,
                # límites efectivos usados por el flujo (Mvar)
                "Qmin_actual_Mvar": attr(g, "cQ_min"),
                "Qmax_actual_Mvar": attr(g, "cQ_max"),
                # límites del elemento en pu de Sgn
                "q_min_pu": attr(g, "q_min"),
                "q_max_pu": attr(g, "q_max"),
                "curva_capacidad": nombre(qlim),
                "curva_tiene_puntos": "",  # se rellena abajo
                "av_mode": attr(g, "av_mode"),
                "usetp_pu": attr(g, "usetp"),
                "ngnum": attr(g, "ngnum"),
                "outserv": attr(g, "outserv"),
            })
            if qlim is None or qlim == "":
                continue
            ruta_q = qlim.GetFullName()
            inputmod = attr(qlim, "inputmod", "")
            # modo 0 → MW/Mvar; modo 1 → pu de Sgn
            p_pts = attr(qlim, "cap_P", []) or attr(qlim, "cap_Ppu", []) or []
            qmn = attr(qlim, "cap_Qmn", []) or []
            qmx = attr(qlim, "cap_Qmx", []) or []
            filas_q[-1]["curva_tiene_puntos"] = int(bool(p_pts and (qmn or qmx)))
            if ruta_q in curvas_vistas:
                continue
            curvas_vistas.add(ruta_q)
            if not p_pts:
                warnings.append("curva %s (%s): sin puntos legibles (inputmod=%s)"
                                % (qlim.loc_name, ruta_q, inputmod))
                continue
            for i, p in enumerate(p_pts):
                filas_curva.append({
                    "curva": qlim.loc_name,
                    "curva_ruta": ruta_q,
                    "inputmod": inputmod,   # 0 = MW/Mvar, 1 = pu de Sgn
                    "punto": i,
                    "P": p,
                    "Qmin": qmn[i] if i < len(qmn) else "",
                    "Qmax": qmx[i] if i < len(qmx) else "",
                })
    escribir_csv(out / "escenario_P20_qcap.csv", filas_q)
    escribir_csv(out / "qcap_curvas.csv", filas_curva)
    con_curva = sum(1 for f in filas_q if f["curva_capacidad"])
    con_puntos = sum(1 for f in filas_q if f["curva_tiene_puntos"] == 1)
    print("  qcap: %d unidades (%d con curva, %d con puntos legibles) | %d puntos"
          % (len(filas_q), con_curva, con_puntos, len(filas_curva)))

    cerrar(out, {
        "proyecto": PROYECTO, "escenario": ESCENARIO_BASE,
        "study_case": nombre(app.GetActiveStudyCase()),
        "fecha": datetime.now().isoformat(),
        "comldf_err": ldf_err,
        "conteos": {"shunts": len(filas), "svc": len(filas_svc),
                    "stactrl": len(filas_st), "generadores": len(filas_q),
                    "puntos_curva": len(filas_curva), "barras": len(tensiones)},
        "sumas": {"Q_shunts_actual_Mvar": round(q_cap, 3)},
    }, warnings)
    return out


# ==================== P3 — puntos de operación P01–P24 ====================

def bloque_op(app, raiz: Path, stamp: str):
    out = raiz / ("salida_op_P01_P24_%s" % stamp)
    out.mkdir(parents=True, exist_ok=True)
    warnings = []
    cargas, gens, taps, shunts, resumen = [], [], [], [], []

    for esc in ESCENARIOS:
        try:
            activar_escenario(app, esc)
        except Exception as e:
            warnings.append("escenario %s: no se pudo activar (%s)" % (esc, e))
            continue
        p_dem = q_dem = p_gen = 0.0
        for lod in app.GetCalcRelevantObjects("*.ElmLod"):
            p, q = attr(lod, "plini", 0.0), attr(lod, "qlini", 0.0)
            fuera = attr(lod, "outserv", 0)
            cargas.append({
                "escenario": esc, "for_name": attr(lod, "for_name"),
                "loc_name": lod.loc_name, "ruta": lod.GetFullName(),
                "P_MW": p, "Q_Mvar": q, "escala": attr(lod, "scale0"),
                "outserv": fuera,
            })
            if fuera == 0:
                p_dem += float(p or 0)
                q_dem += float(q or 0)
        for cl, tag in (("*.ElmSym", "sym"), ("*.ElmGenstat", "genstat")):
            for g in app.GetCalcRelevantObjects(cl):
                b = barra_de(g)
                p = attr(g, "pgini", 0.0)
                n_u = attr(g, "ngnum", 1) or 1
                fuera = attr(g, "outserv", 0)
                gens.append({
                    "escenario": esc, "clase": tag,
                    "for_name": attr(g, "for_name"), "loc_name": g.loc_name,
                    "barra_for_name": attr(b, "for_name") if b else "",
                    "P_desp_MW": p, "Q_desp_Mvar": attr(g, "qgini"),
                    "U_consigna_pu": attr(g, "usetp"),
                    "modo_ctrl_av": attr(g, "av_mode"),
                    "num_unidades": n_u, "outserv": fuera,
                    "ref_slack": attr(g, "ip_ctrl"),
                })
                if fuera == 0:
                    p_gen += float(p or 0) * max(int(n_u), 1)
        for cl in ("*.ElmTr2", "*.ElmTr3"):
            for t in app.GetCalcRelevantObjects(cl):
                taps.append({
                    "escenario": esc, "for_name": attr(t, "for_name"),
                    "loc_name": t.loc_name, "clase": cl[2:],
                    "tap_actual": attr(t, "nntap"),
                    "tap_hv": attr(t, "n3tap_h"), "tap_mv": attr(t, "n3tap_m"),
                    "tap_lv": attr(t, "n3tap_l"),
                    "outserv": attr(t, "outserv"),
                })
        q_sh = 0.0
        for o in app.GetCalcRelevantObjects("*.ElmShnt"):
            ncapa, qcapn = attr(o, "ncapa", 0), attr(o, "qcapn", 0)
            fuera = attr(o, "outserv", 0)
            shunts.append({
                "escenario": esc, "for_name": attr(o, "for_name"),
                "loc_name": o.loc_name, "shtype": attr(o, "shtype"),
                "ncapa": ncapa, "ncapx": attr(o, "ncapx"),
                "qcapn_Mvar_paso": qcapn, "outserv": fuera,
            })
            if fuera == 0:
                q_sh += float(ncapa or 0) * float(qcapn or 0)
        resumen.append({
            "escenario": esc, "demanda_P_MW": round(p_dem, 3),
            "demanda_Q_Mvar": round(q_dem, 3),
            "generacion_P_MW": round(p_gen, 3),
            "Q_shunts_nominal_Mvar": round(q_sh, 3),
        })
        print("  %s: demanda %.1f MW | gen %.1f MW | shunts %.1f Mvar"
              % (esc, p_dem, p_gen, q_sh))

    activar_escenario(app, ESCENARIO_BASE)  # restaurar SIEMPRE
    escribir_csv(out / "op_cargas_P01_P24.csv", cargas)
    escribir_csv(out / "op_generacion_P01_P24.csv", gens)
    escribir_csv(out / "op_taps_P01_P24.csv", taps)
    escribir_csv(out / "op_shunts_P01_P24.csv", shunts)
    escribir_csv(out / "resumen_por_escenario.csv", resumen)
    cerrar(out, {
        "proyecto": PROYECTO, "escenarios": ESCENARIOS,
        "escenario_restaurado": ESCENARIO_BASE,
        "fecha": datetime.now().isoformat(),
        "conteos": {"cargas": len(cargas), "generacion": len(gens),
                    "taps": len(taps), "shunts": len(shunts)},
    }, warnings)
    return out


# ==================== P4 + P5 — AGC y parámetros hidro ====================

def dsls_de_maquina(g):
    """DSLs del composite model de la máquina (AVR/GOV/PSS...)."""
    comp = attr(g, "c_pmod", None)
    if comp in (None, ""):
        return []
    try:
        return comp.GetContents("*.ElmDsl")
    except Exception:
        return []


def modelo_de(d):
    t = attr(d, "typ_id", None)
    return nombre(t)


def bloque_agc(app, raiz: Path, stamp: str):
    out = raiz / ("salida_agc_hidro_%s" % stamp)
    out.mkdir(parents=True, exist_ok=True)
    warnings = []

    # ¿existe un objeto de control secundario/AGC en el modelo?
    inventario = {}
    for cl in ("ElmSecctrl", "ElmAgc", "ElmFreqctrl", "ElmArea", "ElmZone",
               "ElmStactrl"):
        inventario[cl] = len(app.GetCalcRelevantObjects("*." + cl))
    if inventario["ElmSecctrl"] == 0 and inventario["ElmAgc"] == 0 \
            and inventario["ElmFreqctrl"] == 0:
        warnings.append("AGC: el proyecto NO tiene ElmSecctrl/ElmAgc/ElmFreqctrl — "
                        "no hay control secundario modelado; agc_participacion.csv "
                        "reporta la capacidad regulante por gobernador (proxy)")

    # máquinas gobernadas por cada station controller (control de tensión)
    en_stactrl = {}
    for sc in app.GetCalcRelevantObjects("*.ElmStactrl"):
        for m in (attr(sc, "psym", []) or []):
            if m is not None:
                en_stactrl[m.GetFullName()] = sc.loc_name

    filas, filas_gov, filas_hidro = [], [], []
    for g in app.GetCalcRelevantObjects("*.ElmSym"):
        typ = attr(g, "typ_id", None)
        dsls = dsls_de_maquina(g)
        gov = None
        for d in dsls:
            m = modelo_de(d).lower()
            if any(k in m for k in ("gov", "pcu", "pmu", "eng")):
                gov = d
                break
        gov_modelo = modelo_de(gov) if gov is not None else ""
        # estatismo permanente del gobernador
        droop, droop_param = "", ""
        params = {}
        if gov is not None:
            t = attr(gov, "typ_id", None)
            nombres = []
            for s in (attr(t, "sParams", []) or []):
                nombres.extend(p.strip() for p in str(s).split(",") if p.strip())
            for n in nombres:
                v = attr(gov, n, None)
                if v is not None and not hasattr(v, "loc_name"):
                    params[n] = v
            for cand in CLAVES_DROOP:
                if cand in params and isinstance(params[cand], (int, float)) \
                        and params[cand] != 0:
                    droop, droop_param = params[cand], cand
                    break
            for k, v in params.items():
                filas_gov.append({
                    "maquina_for_name": attr(g, "for_name"),
                    "maquina_loc_name": g.loc_name,
                    "gov_modelo": gov_modelo, "gov_dsl": gov.loc_name,
                    "param": k, "valor": v,
                })
        p_max = attr(g, "Pmax_uc", "")
        filas.append({
            "for_name": attr(g, "for_name"),
            "loc_name": g.loc_name,
            "area": nombre(attr(g, "cpArea", None)),
            "P_desp_MW": attr(g, "pgini"),
            "Pmin_MW": attr(g, "Pmin_uc"),
            "Pmax_MW": p_max,
            "num_unidades": attr(g, "ngnum"),
            "sgn_MVA": attr(typ, "sgn") if typ else "",
            "tiene_gobernador": int(gov is not None),
            "gov_modelo": gov_modelo,
            "estatismo_droop": droop,
            "droop_param": droop_param,
            # margen regulante disponible en P20 (proxy de participación AGC)
            "margen_subida_MW": (
                round(float(p_max or 0) - float(attr(g, "pgini", 0) or 0), 3)
                if p_max not in ("", None) else ""),
            "station_controller": en_stactrl.get(g.GetFullName(), ""),
            "ref_slack": attr(g, "ip_ctrl"),
            "outserv": attr(g, "outserv"),
        })

        # ---- hidro ----
        es_hidro = any(any(k in modelo_de(d).upper() for k in CLAVES_HIDRO)
                       for d in dsls)
        if es_hidro:
            fila_h = {
                "for_name": attr(g, "for_name"),
                "loc_name": g.loc_name,
                "P_nominal_MW": p_max,
                "sgn_MVA": attr(typ, "sgn") if typ else "",
                "iturbo": attr(typ, "iturbo") if typ else "",
                "num_unidades": attr(g, "ngnum"),
                "outserv": attr(g, "outserv"),
            }
            for d in dsls:
                mod = modelo_de(d)
                if not any(k in mod.upper() for k in CLAVES_HIDRO):
                    continue
                t = attr(d, "typ_id", None)
                nombres = []
                for s in (attr(t, "sParams", []) or []):
                    nombres.extend(p.strip() for p in str(s).split(",") if p.strip())
                fila_h.setdefault("modelos", [])
                fila_h["modelos"].append(mod)
                for n in nombres:
                    v = attr(d, n, None)
                    if v is None or hasattr(v, "loc_name"):
                        continue
                    fila_h["%s.%s" % (mod, n)] = v
            fila_h["modelos"] = ";".join(fila_h.get("modelos", []))
            filas_hidro.append(fila_h)

    escribir_csv(out / "agc_participacion.csv", filas)
    escribir_csv(out / "gov_parametros.csv", filas_gov)
    escribir_csv(out / "hidro_parametros.csv", filas_hidro)
    con_gov = sum(1 for f in filas if f["tiene_gobernador"] == 1)
    en_serv = [f for f in filas if f["outserv"] == 0]
    margen = sum(float(f["margen_subida_MW"] or 0) for f in en_serv
                 if f["tiene_gobernador"] == 1)
    print("  máquinas: %d (%d en servicio, %d con gobernador)"
          % (len(filas), len(en_serv), con_gov))
    print("  margen regulante (gobernadas, en servicio): %.1f MW" % margen)
    print("  hidro: %d máquinas | %d parámetros de gobernador"
          % (len(filas_hidro), len(filas_gov)))

    cerrar(out, {
        "proyecto": PROYECTO, "escenario": ESCENARIO_BASE,
        "fecha": datetime.now().isoformat(),
        "inventario_clases_control": inventario,
        "conteos": {"maquinas": len(filas), "con_gobernador": con_gov,
                    "hidro": len(filas_hidro), "params_gov": len(filas_gov)},
        "margen_regulante_MW": round(margen, 3),
    }, warnings)
    return out


# ==================== P6 — arrays FRT (oarray) ====================

def bloque_frt(app, raiz: Path, stamp: str):
    out = raiz / ("salida_oarray_frt_%s" % stamp)
    out.mkdir(parents=True, exist_ok=True)
    warnings = []
    filas, resumen = [], []

    # planta (ElmComp) → generadores estáticos que contiene
    for d in app.GetCalcRelevantObjects("*.ElmDsl"):
        t = attr(d, "typ_id", None)
        if t in (None, ""):
            continue
        nombres = []
        for s in (attr(t, "sParams", []) or []):
            nombres.extend(p.strip() for p in str(s).split(",") if p.strip())
        arrays = [n for n in nombres if n.lower().startswith(("array", "oarray", "matrix"))]
        if not arrays:
            continue
        encriptado = "Encrypted" in str(attr(t, "sAddEquat", ""))
        comp = d.GetParent()
        planta = nombre(comp)
        # los valores viven en objetos IntMat hijos del ElmDsl (o de su BlkDef),
        # cuyo loc_name es el del parámetro sin el prefijo array_/oarray_
        mats = {}
        for m in list(d.GetContents("*.IntMat")) + list(t.GetContents("*.IntMat")):
            mats[m.loc_name.strip().lower()] = m
        for nom in arrays:
            base = nom.split("_", 1)[1].lower() if "_" in nom else nom.lower()
            mat = mats.get(base) or mats.get(nom.lower())
            origen = ""
            datos = None
            if mat is not None:
                datos = attr(mat, "matrix", None) or attr(mat, "M", None)
                origen = "IntMat:" + mat.loc_name
            if not datos:
                # accesor por parámetro ("matrix:<nombre>" es el que responde)
                datos = attr(d, "matrix:" + nom, None) or attr(d, nom, None)
                origen = origen or "param"
            n_val = 0
            if isinstance(datos, (list, tuple)):
                for i, fila in enumerate(datos):
                    if isinstance(fila, (list, tuple)):
                        for j, v in enumerate(fila):
                            filas.append({
                                "planta": planta, "dsl": d.loc_name,
                                "dsl_ruta": d.GetFullName(), "modelo": t.loc_name,
                                "array": nom, "origen": origen,
                                "fila": i, "columna": j, "valor": v,
                            })
                            n_val += 1
                    else:
                        filas.append({
                            "planta": planta, "dsl": d.loc_name,
                            "dsl_ruta": d.GetFullName(), "modelo": t.loc_name,
                            "array": nom, "origen": origen,
                            "fila": i, "columna": 0, "valor": fila,
                        })
                        n_val += 1
            resumen.append({
                "planta": planta, "dsl": d.loc_name,
                "dsl_ruta": d.GetFullName(), "modelo": t.loc_name,
                "array": nom, "origen": origen, "n_valores": n_val,
                "modelo_encriptado": int(encriptado),
                "legible": int(n_val > 0),
            })
            if n_val == 0:
                warnings.append(
                    "%s / %s / %s: array vacío%s"
                    % (planta, d.loc_name, nom,
                       " (modelo DSL ENCRIPTADO)" if encriptado else ""))

    escribir_csv(out / "oarray_frt_completo.csv", filas)
    escribir_csv(out / "oarray_frt_resumen.csv", resumen)
    n_leg = sum(1 for r in resumen if r["legible"])
    n_enc = sum(1 for r in resumen if r["modelo_encriptado"] and not r["legible"])
    print("  arrays: %d (%d con datos, %d vacíos por modelo encriptado) | %d valores"
          % (len(resumen), n_leg, n_enc, len(filas)))
    cerrar(out, {
        "proyecto": PROYECTO, "escenario": ESCENARIO_BASE,
        "fecha": datetime.now().isoformat(),
        "conteos": {"arrays": len(resumen), "legibles": n_leg,
                    "vacios_encriptados": n_enc, "valores": len(filas)},
    }, warnings)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--solo", choices=["shunts", "op", "agc", "frt"],
                    help="correr un solo bloque")
    ap.add_argument("--salida", default="data/raw")
    args = ap.parse_args()

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    raiz = Path(args.salida)
    app = conectar()
    if app.ActivateProject(PROYECTO):
        raise RuntimeError("No se pudo activar el proyecto %s" % PROYECTO)
    activar_escenario(app, ESCENARIO_BASE)
    print("Proyecto %s | escenario %s | study case %s"
          % (PROYECTO, ESCENARIO_BASE, nombre(app.GetActiveStudyCase())))

    bloques = [(args.solo,)] if args.solo else [("shunts",), ("op",), ("agc",), ("frt",)]
    salidas = []
    try:
        for (b,) in bloques:
            print("[%s]" % b)
            salidas.append({"shunts": bloque_shunts, "op": bloque_op,
                            "agc": bloque_agc, "frt": bloque_frt}[b](app, raiz, stamp))
    finally:
        try:
            activar_escenario(app, ESCENARIO_BASE)
            print("Escenario restaurado a %s" % ESCENARIO_BASE)
        except Exception as e:
            print("AVISO: no se pudo restaurar %s (%s)" % (ESCENARIO_BASE, e))
    for s in salidas:
        print("Salida:", s)


if __name__ == "__main__":
    sys.exit(main())
