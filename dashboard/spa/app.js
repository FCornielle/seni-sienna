import { render } from 'preact'
import { useState, useEffect, useRef } from 'preact/hooks'
import { html } from 'htm/preact'
import * as L from 'leaflet'
import katex from 'katex'

// ------------------------------------------------------------------ API ----
const j = async (u, o) => { const r = await fetch(u, o); if (!r.ok) throw new Error(`${u} ${r.status}`); return r.json() }
const api = {
  corridas: () => j('/api/corridas'),
  lanzar: (id) => j(`/api/corridas/${id}`, { method: 'POST' }),
  log: (id) => j(`/api/log/${id}`),
  resultados: () => j('/api/resultados'),
  tabla: (n) => j(`/api/tabla/${encodeURIComponent(n)}`),
  doc: (n) => j(`/api/doc/${encodeURIComponent(n)}`),
  generadores: () => j('/api/generadores'),
  escenario: () => j('/api/escenario'),
  correrEscenario: (b) => j('/api/escenario', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b) }),
  feedOc: () => j('/api/feed_oc'),
  mapa: (c) => j(`/api/mapa?capa=${c || 'kv'}`),
}
const fig = (n) => `/figuras/${n}`

// -------------------------------------------------------------- markdown ----
function renderMd(s) {
  s = s.replace(/&/g, '&amp;').replace(/</g, '&lt;')
  const out = []; let t = false
  for (let ln of s.split('\n')) {
    if (/^\|/.test(ln)) {
      if (/^\|[\s\-|:]+\|$/.test(ln.trim())) continue
      const c = ln.split('|').slice(1, -1).map((x) => x.trim())
      if (!t) { out.push('<table>'); t = true; out.push('<tr>' + c.map((x) => `<th>${x}</th>`).join('') + '</tr>') }
      else out.push('<tr>' + c.map((x) => `<td>${x}</td>`).join('') + '</tr>')
      continue
    } else if (t) { out.push('</table>'); t = false }
    ln = ln.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/`([^`]+)`/g, '<code>$1</code>').replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1')
    if (/^### /.test(ln)) out.push('<h3>' + ln.slice(4) + '</h3>')
    else if (/^## /.test(ln)) out.push('<h2>' + ln.slice(3) + '</h2>')
    else if (/^# /.test(ln)) out.push('<h2>' + ln.slice(2) + '</h2>')
    else if (/^- /.test(ln)) out.push('<li>' + ln.slice(2) + '</li>')
    else if (/^> /.test(ln)) out.push('<p style="color:var(--mut);border-left:3px solid var(--bd);padding-left:10px">' + ln.slice(2) + '</p>')
    else if (ln.trim() === '---') out.push('<hr>')
    else out.push(ln.trim() === '' ? '' : '<p>' + ln + '</p>')
  }
  if (t) out.push('</table>')
  return out.join('\n')
}

// ----------------------------------------------------------------- Mapa -----
const CAPAS = [['kv', 'Nivel de tensión'], ['vpu', 'Tensión del flujo (pu)'], ['edac', 'Deslastre EDAC']]
const colorKv = (kv) => kv >= 345 ? '#d6336c' : kv >= 138 ? '#1971c2' : kv >= 69 ? '#2f9e44' : '#868e96'
const colorV = (v) => v == null ? '#adb5bd' : v < 0.95 ? '#e03131' : v > 1.05 ? '#f08c00' : '#2f9e44'
const LEY = {
  kv: [['#d6336c', '345 kV'], ['#1971c2', '138 kV'], ['#2f9e44', '69 kV'], ['#868e96', 'otros']],
  vpu: [['#e03131', '< 0.95 pu'], ['#2f9e44', '0.95–1.05 pu'], ['#f08c00', '> 1.05 pu'], ['#adb5bd', 'sin dato']],
  edac: [['#7048e8', 'alimentador EDAC'], ['#ced4da', 'sin deslastre']],
}

function Mapa() {
  const [capa, setCapa] = useState('kv')
  const [datos, setDatos] = useState(null)
  const [err, setErr] = useState(null)
  const el = useRef(null), map = useRef(null), lg = useRef(null)

  useEffect(() => {
    const m = L.map(el.current, { preferCanvas: true }).setView([18.75, -70.4], 8)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '© OpenStreetMap', maxZoom: 18 }).addTo(m)
    map.current = m; lg.current = L.layerGroup().addTo(m)
    return () => m.remove()
  }, [])

  useEffect(() => { setErr(null); api.mapa(capa).then(setDatos).catch((e) => setErr(String(e))) }, [capa])

  useEffect(() => {
    if (!lg.current || !datos) return
    lg.current.clearLayers()
    for (const b of datos.barras) {
      let col, rad
      if (capa === 'vpu') { col = colorV(b.vpu); rad = b.kv >= 345 ? 7 : b.kv >= 138 ? 5.5 : 4 }
      else if (capa === 'edac') { col = b.edac_mw > 0 ? '#7048e8' : '#ced4da'; rad = b.edac_mw > 0 ? 5 + Math.min(b.edac_mw / 20, 12) : 2.5 }
      else { col = colorKv(b.kv); rad = b.kv >= 345 ? 7 : b.kv >= 138 ? 5.5 : 4 }
      let tip = `<b>${b.nombre}</b> (${b.id})<br>${b.kv} kV`
      if (capa === 'vpu' && b.vpu != null) tip += `<br>V = ${b.vpu.toFixed(3)} pu`
      if (capa === 'edac' && b.edac_mw > 0) tip += `<br>EDAC: ${b.edac_mw.toFixed(1)} MW`
      L.circleMarker([b.lat, b.lon], { radius: rad, color: col, fillColor: col, fillOpacity: 0.75, weight: 1 })
        .bindTooltip(tip).addTo(lg.current)
    }
  }, [datos, capa])

  return html`
    <div class="mapwrap">
      <div class="legend">
        <div class="capsel">
          <h4>Capa</h4>
          ${CAPAS.map(([id, l]) => html`<label key=${id}><input type="radio" checked=${capa === id} onChange=${() => setCapa(id)} /> ${l}</label>`)}
        </div>
        <h4>Leyenda</h4>
        ${LEY[capa].map(([c, l]) => html`<div class="li" key=${l}><span class="dot" style=${{ background: c }}></span> ${l}</div>`)}
        <div style="margin-top:12px;font-size:12px;color:var(--mut)">${datos?.barras.length ?? 0} barras · ${datos?.con_dato ?? 0} con dato</div>
        ${err && html`<div style="color:var(--err);font-size:12px;margin-top:8px">${err}</div>`}
      </div>
      <div id="map" ref=${el}></div>
    </div>`
}

// -------------------------------------------------------------- Corridas ----
function Corridas() {
  const [cs, setCs] = useState([]); const [sel, setSel] = useState(''); const [log, setLog] = useState('')
  useEffect(() => {
    const f = () => api.corridas().then((t) => { const l = t.filter((c) => c.id !== 'escenario'); setCs(l); setSel((s) => s || (l[0]?.id ?? '')) })
    f(); const iv = setInterval(f, 3000); return () => clearInterval(iv)
  }, [])
  useEffect(() => {
    if (!sel) return
    const f = () => api.log(sel).then((r) => setLog(r.texto || '(log vacío)'))
    f(); const iv = setInterval(f, 3000); return () => clearInterval(iv)
  }, [sel])
  const lanzar = async (id) => { await api.lanzar(id); setSel(id) }
  return html`
    <div class="grid">
      ${cs.map((c) => html`
        <div class="card" key=${c.id}>
          <h3>${c.nombre}</h3><div class="d">${c.desc}</div>
          <div class="fila">
            <span class="badge ${c.estado}">${c.estado}</span>
            <span style="color:var(--mut);font-size:11.5px">${c.script}</span>
            <button class="run" disabled=${c.estado === 'corriendo'} onClick=${() => lanzar(c.id)}>Ejecutar</button>
          </div>
        </div>`)}
    </div>
    <div class="sec">Log de la corrida</div>
    <select value=${sel} onChange=${(e) => setSel(e.target.value)}>
      ${cs.map((c) => html`<option value=${c.id} key=${c.id}>${c.nombre}</option>`)}
    </select>
    <pre class="log">${log}</pre>`
}

// ------------------------------------------------------------- Escenario ----
function Escenario() {
  const [gens, setGens] = useState([]); const [ds, setDs] = useState(1.0); const [rp, setRp] = useState(3)
  const [dis, setDis] = useState([]); const [resumen, setResumen] = useState(null); const [log, setLog] = useState(''); const [run, setRun] = useState(false)
  const refrescar = () => { api.escenario().then((r) => setResumen(r.resumen)); api.log('escenario').then((r) => setLog(r.texto || '')) }
  useEffect(() => { api.generadores().then((r) => setGens(r.generadores || [])); refrescar() }, [])
  const toggle = (id) => setDis((d) => d.includes(id) ? d.filter((x) => x !== id) : [...d, id])
  const ejecutar = async () => {
    setRun(true)
    await api.correrEscenario({ demand_scale: ds, reserve_pct: rp / 100, gen_disabled: dis, cvp_mult: {} })
    const iv = setInterval(async () => {
      const cs = await api.corridas(); const e = cs.find((c) => c.id === 'escenario'); refrescar()
      if (e && e.estado !== 'corriendo') { clearInterval(iv); setRun(false) }
    }, 3000)
  }
  return html`
    <div style="display:grid;grid-template-columns:360px 1fr;gap:20px">
      <div class="card">
        <h3>Perillas del escenario</h3>
        <div class="d">Corre un UC alternativo; se compara contra la línea base.</div>
        <div style="margin-top:12px"><label style="font-size:13px">Demanda × <b>${ds.toFixed(2)}</b></label>
          <input type="range" min="0.7" max="1.3" step="0.01" value=${ds} style="width:100%" onInput=${(e) => setDs(+e.target.value)} /></div>
        <div style="margin-top:10px"><label style="font-size:13px">Reserva RPF/RSF: <b>${rp}</b>%</label>
          <input type="range" min="0" max="8" step="0.5" value=${rp} style="width:100%" onInput=${(e) => setRp(+e.target.value)} /></div>
        <div style="margin-top:10px"><label style="font-size:13px">Unidades fuera de servicio</label>
          <div class="scroll" style="max-height:180px;margin-top:4px">
            ${gens.map((g) => html`<label key=${g.id} style="display:block;font-size:12.5px;padding:2px 6px;cursor:pointer">
              <input type="checkbox" checked=${dis.includes(g.id)} onChange=${() => toggle(g.id)} /> ${g.nombre} (${g.pmax} MW)</label>`)}
          </div></div>
        <button class="run" style="margin-top:14px;width:100%" disabled=${run} onClick=${ejecutar}>${run ? 'Corriendo…' : 'Ejecutar escenario (UC)'}</button>
      </div>
      <div>
        ${resumen ? html`<div class="scroll"><table>
            <thead><tr>${resumen.columnas.map((c) => html`<th key=${c}>${c}</th>`)}</tr></thead>
            <tbody>${resumen.filas.map((f, i) => html`<tr key=${i}>${f.map((v, k) => html`<td key=${k}>${v}</td>`)}</tr>`)}</tbody>
          </table></div>` : html`<div class="card">Ejecuta un escenario para ver el delta vs base.</div>`}
        <img src=${fig('f8_scenario_studio.png') + '?' + Date.now()} style="width:100%;margin-top:12px;border:1px solid var(--bd);border-radius:8px" onError=${(e) => (e.target.style.display = 'none')} />
        <pre class="log">${log || '(sin corridas de escenario)'}</pre>
      </div>
    </div>`
}

// ------------------------------------------------------------ Resultados ----
function Resultados() {
  const [res, setRes] = useState(null); const [csv, setCsv] = useState(''); const [tab, setTab] = useState(null)
  useEffect(() => { api.resultados().then((r) => { setRes(r); if (r.tablas?.length) setCsv(r.tablas[0]) }) }, [])
  useEffect(() => { if (csv) api.tabla(csv).then(setTab) }, [csv])
  return html`
    <div class="sec">Figuras</div>
    <div class="figs">${res?.figuras.map((f) => html`<figure key=${f}><img src=${fig(f)} /><figcaption style="color:var(--mut);font-size:12px;padding:4px 2px">${f}</figcaption></figure>`)}</div>
    <div class="sec">Tablas de validación</div>
    <select value=${csv} onChange=${(e) => setCsv(e.target.value)}>${res?.tablas.map((t) => html`<option key=${t}>${t}</option>`)}</select>
    <div class="scroll" style="margin-top:10px">
      ${tab && html`<table><thead><tr>${tab.columnas.map((c) => html`<th key=${c}>${c}</th>`)}</tr></thead>
        <tbody>${tab.filas.map((f, i) => html`<tr key=${i}>${f.map((v, k) => html`<td key=${k}>${v}</td>`)}</tr>`)}</tbody></table>`}
    </div>`
}

// --------------------------------------------------------------- Reporte ----
function Reporte() {
  const [docs, setDocs] = useState([]); const [sel, setSel] = useState(''); const [h, setH] = useState('')
  useEffect(() => { api.resultados().then((r) => { const p = 'REPORTE_SENI_SIENNA.md'; const o = [...r.docs.filter((d) => d === p), ...r.docs.filter((d) => d !== p)]; setDocs(o); if (o.length) setSel(o[0]) }) }, [])
  useEffect(() => { if (sel) api.doc(sel).then((r) => setH(renderMd(r.texto))) }, [sel])
  return html`
    <select value=${sel} onChange=${(e) => setSel(e.target.value)} style="margin-bottom:12px">${docs.map((d) => html`<option key=${d}>${d}</option>`)}</select>
    <div class="doc" dangerouslySetInnerHTML=${{ __html: h }}></div>`
}

// ----------------------------------------------------------------- Datos ----
function Datos() {
  const [f, setF] = useState(null)
  useEffect(() => { api.feedOc().then(setF) }, [])
  return html`
    <div class="card" style="max-width:820px">
      <h3>Procedencia de los datos</h3><div class="d">Origen de cada insumo (nada de esto se versiona en git).</div>
      <div class="scroll" style="margin-top:10px"><table>
        <thead><tr><th>Insumo</th><th>Estado</th><th>Origen</th></tr></thead>
        <tbody>${f?.items.map((i) => html`<tr key=${i.nombre}><td>${i.nombre}</td>
          <td style=${{ color: i.ok ? 'var(--ok)' : 'var(--err)' }}>${i.ok ? 'presente' : 'falta'}</td><td>${i.origen}</td></tr>`)}</tbody>
      </table></div>
      ${f && html`<p style="margin-top:12px;font-size:13px;color:var(--mut)">Recurso OC: <a href=${f.recurso} target="_blank">${f.recurso}</a></p>`}
    </div>`
}

// ---------------------------------------------------------- Metodología ----
const Eq = ({ tex, lbl, cob }) => {
  const mhtml = katex.renderToString(tex, { displayMode: true, output: 'mathml', throwOnError: false })
  const pill = { si: 'Implementada', par: 'Parcial', no: 'No / gap' }[cob]
  return html`<div class="eq">${lbl && html`<div class="lbl">${lbl}${cob && html`<span class="pill ${cob}">${pill}</span>`}</div>`}
    <div dangerouslySetInnerHTML=${{ __html: mhtml }}></div></div>`
}
const S = String.raw
function Metodologia() {
  const secs = [['m1', 'MODOM · Objetivo'], ['m2', 'MODOM · Red y balance'], ['m3', 'MODOM · Reservas'], ['m4', 'MODOM · UC, rampas, arranques'], ['m5', 'MODOM · Hídrico'], ['s1', 'Sienna · Data'], ['s2', 'Sienna · Ops'], ['s3', 'Sienna · Dyn'], ['c', 'Criterios']]
  return html`
    <div class="metod">
      <nav class="toc"><div class="sec" style="margin:0 0 6px">Contenido</div>${secs.map(([id, t]) => html`<a href="#${id}" key=${id}>${t}</a>`)}</nav>
      <div class="doc">
        <p style="color:var(--mut)">Correspondencia entre la formulación MODOM del OC (Programación de Corto Plazo) y su implementación en Sienna, más las consideraciones y criterios propios de Sienna. Etiquetas de cobertura: <span class="pill si">Implementada</span> <span class="pill par">Parcial</span> <span class="pill no">No / gap</span>.</p>

        <h2 id="m1">MODOM · Función objetivo</h2>
        <p>Minimiza costo variable térmico, ENS, vertimiento renovable, penalización de reservas y arranque/parada:</p>
        ${html`<${Eq} lbl="§6.1 — Costo total Z" cob="par" tex=${S`Z=\sum_{n}\sum_{g\in G_t} CVP_g^{ef}P_{n,g}+CENS\sum_n PNS_n^{tot}+\sum_n\sum_e CVERR\,VERT_{n,e}+CVRRF\!\sum_n\!\sum_{g\in G_{RSF}}\!\xi_{n,g}^{RSF}+\sum_n\sum_{g\in G_t}\!\big(C_g^{ARR}u_{n,g}^{ARR}+C_g^{PAR}u_{n,g}^{PAR}\big)`} />`}
        <p>En Sienna: costo variable lineal (curva CVP), ENS/vertido con costo CENS en el LP (script 03) y arranques en el UC (script 04, <code>CVP·PMN·TARR</code>).</p>

        <h2 id="m2">MODOM · Red y balance</h2>
        ${html`<${Eq} lbl="§7.15 — Balance nodal" cob="si" tex=${S`\sum_{g\in G_{nd}}P_{n,g}+\!\!\sum_{\ell:nf=nd}\!\!F_{n,\ell}+PNS_{n,nd}=D_{n,nd}+\!\!\sum_{\ell:ni=nd}\!\!F_{n,\ell}+\sum_{g\in G_{nd}}SSA_{n,g}+PERD_{n,nd}`} />`}
        ${html`<${Eq} lbl="§7.13.1 — Ley de flujo DC" cob="si" tex=${S`F_{\ell,n}=\frac{S^{BASE}}{X_\ell}\left(\theta_{ni,n}-\theta_{nf,n}\right)`} />`}
        ${html`<${Eq} lbl="§7.13 — Límites térmicos y flowgates" cob="si" tex=${S`-FLJMAX_\ell\le F_{\ell,n}\le FLJMAX_\ell,\qquad \sum_{\ell\in fg}c_\ell F_{\ell,n}\le FG^{max}_{fg}`} />`}
        <p>Red DC por ángulos (LP) y <code>PTDFPowerModel</code> (UC); flowgates como <code>TransmissionInterface</code>. Hallazgo validado: MODOM es un modelo de transporte — sin límites térmicos por rama, solo flowgates (con ellos R²=0.913; sin ellos R²=0.957). Verificación AC con PowerFlows.jl.</p>

        <h2 id="m3">MODOM · Reservas (RPF / RSF / AGC)</h2>
        ${html`<${Eq} lbl="§7.4.1 — Requisito RPF (3%, Art. 399)" cob="si" tex=${S`\sum_{g\in G_{RPF}}\!\big(MR^{RPF}_{n,g}+\xi^{RPF}_{n,g}\big)\ge RRPF_n\!\!\sum_{g\in G_{act}}\!\!P_{n,g}`} />`}
        ${html`<${Eq} lbl="§7.4.2 — Requisito RSF" cob="par" tex=${S`\sum_{g\in G_{RSF}}\!\big(MR^{RSF}_{n,g}+HSF_{g,n}v^{ACC}_{n,g}+\xi^{RSF}_{n,g}\big)+\sum_{g\in G_{AGC}}\!MR^{AGC}_{n,g}\ge RRSF_n\!\!\sum_g P_{n,g}`} />`}
        <p>RPF y RSF como <code>VariableReserve{ReserveUp}</code> co-optimizadas en el UC (<code>RangeReserve</code>), 3% de la demanda. Hidro excluida como contribuyente por un bug de HydroPowerSimulations 0.11 + PSI 0.30. AGC no separado aún.</p>

        <h2 id="m4">MODOM · Compromiso, rampas y arranques</h2>
        ${html`<${Eq} lbl="§7.1.1 — Estados excluyentes" cob="par" tex=${S`v^{ACC}_{n,g}+u^{ARR}_{n,g}\mathbf 1_{TARR_g\ge1}+u^{PAR}_{n,g}\mathbf 1_{TPAR_g\ge1}+v^{RFA}_{n,g}=1`} />`}
        ${html`<${Eq} lbl="§7.7.1 — Rampa de subida" cob="si" tex=${S`P_{n+1,g}-P_{n,g}\le RS_g\,v^{ACCS}_{n,g}`} />`}
        ${html`<${Eq} lbl="§7.8 / §7.11.2 — Tiempo mínimo y nº máx. arranques" cob="par" tex=${S`\sum_{t\in\mathcal T_{vent}}u^{ARR2}_{t,g}\ge TARR_g\,u^{ARR}_{n,g},\qquad \sum_n u^{ARR}_{n,g}\le NAMX_g`} />`}
        <p><code>ThermalStandardUnitCommitment</code>: commitment binario, rampas (RS/RB), tiempos mínimos (TMO/TMPA), estado inicial (YN). Los estados multi-etapa ACC/ARR/PAR/RFA se colapsan al on/off de PSI; NAMX/RFA pendientes. Coincidencia vs MODOM: 89.9%.</p>

        <h2 id="m5">MODOM · Balance hídrico</h2>
        ${html`<${Eq} lbl="§7.18.1 — Balance del embalse" cob="par" tex=${S`V^{emb}_{n+1,e}=V^{emb}_{n,e}+\big(A_{n,e}-\!\!\sum_{g\in G_e}\!Q_{n,g}-VERT^{hid}_{n,e}\big)\Delta t`} />`}
        <p>Hidro como <code>HydroDispatchRunOfRiver</code> con techo de disponibilidad horaria. Presupuesto de energía por embalse: refinamiento pendiente.</p>

        <h2 id="s1">Sienna · Data — System y flujo</h2>
        <p><b>PowerSystems.jl</b>: 717 barras (despacho) y 718 nodos (físico, fusión node-breaker de 5 177 terminales). Componentes ACBus, Line, Transformer2W/TapTransformer, generadores, cargas, shunts, reservas, TransmissionInterface.</p>
        ${html`<${Eq} lbl="PowerFlows.jl — flujo AC (Newton-Raphson)" tex=${S`P_i=V_i\sum_j V_j(G_{ij}\cos\theta_{ij}+B_{ij}\sin\theta_{ij}),\quad Q_i=V_i\sum_j V_j(G_{ij}\sin\theta_{ij}-B_{ij}\cos\theta_{ij})`} />`}
        <p>Con el punto P20 exacto + control secundario de tensión + límites de reactiva: |ΔV| medio = 0.006 pu vs PowerFactory.</p>
        ${html`<${Eq} lbl="PowerNetworkMatrices.jl — LODF (N-1)" tex=${S`F^{post}_{\ell}=F^0_{\ell}+LODF_{\ell,k}\,F^0_{k}`} />`}

        <h2 id="s2">Sienna · Ops — despacho y UC</h2>
        <p><b>PowerSimulations.jl</b>: plantillas <code>EconomicDispatch</code>/<code>ThermalStandardUnitCommitment</code>, red PTDF, reservas y flowgates, con HiGHS. Réplica del despacho MODOM: R²=0.957. El Scenario Studio re-optimiza el UC con perillas.</p>

        <h2 id="s3">Sienna · Dyn — dinámica (PSID)</h2>
        <p><b>PowerSimulationsDynamics.jl</b>: cada máquina como DynamicGenerator (máquina + eje + AVR + governor + PSS), sistema diferencial-algebraico. Parámetros reales del export DIgSILENT (GENROU/GENSAL, HYGOV/GGOV1/DEGOV1, EXAC1/IEEET1).</p>
        ${html`<${Eq} lbl="Ecuación de oscilación (swing)" tex=${S`\frac{2H}{\omega_s}\frac{d^2\delta}{dt^2}=P_m-P_e-D\,\Delta\omega`} />`}
        ${html`<${Eq} lbl="Frecuencia del centro de inercia (COI)" tex=${S`f_{COI}=\frac{\sum_g H_g S_g\,\omega_g}{\sum_g H_g S_g}\,f_0`} />`}
        <p>Pequeña señal: 22 modos electromecánicos con ζ&lt;10% (26 en PF). Frecuencia: pérdida de Punta Catalina 2 (360 MW) → nadir 59.43 Hz (PF 59.285). Sobredeslastre EDAC: abrir circuitos completos deslastra 1.39× la pérdida y provoca sobrefrecuencia; el selectivo (30% por alimentador) recupera mejor con 3.3× menos carga.</p>

        <h2 id="c">Criterios de aceptación (Código de Conexión, Ley 125-01)</h2>
        <p>Veredictos por deltas (<code>src/verdicts.jl</code>), estilo Feasibility-Study — solo lo introducido o empeorado:</p>
        <ul>
          <li><b>Tensión</b>: 0.95–1.05 pu en barras ≥ 69 kV.</li>
          <li><b>N-1</b>: sin sobrecargas nuevas de rama (LODF + AC).</li>
          <li><b>Frecuencia</b>: nadir ≥ 59.2 Hz (primer escalón EDAC).</li>
          <li><b>Amortiguamiento</b>: sin reducir el ζ de los modos electromecánicos.</li>
          <li><b>Cortocircuito</b> (IEC 60909): gap — fuera de Sienna (PowerFactory/pandapower).</li>
        </ul>
      </div>
    </div>`
}

// ------------------------------------------------------------------ App -----
const TABS = [['mapa', 'Mapa', Mapa], ['corridas', 'Corridas', Corridas], ['escenario', 'Escenario', Escenario],
  ['resultados', 'Resultados', Resultados], ['reporte', 'Reporte', Reporte], ['metodologia', 'Metodología', Metodologia], ['datos', 'Datos', Datos]]

function App() {
  const [tab, setTab] = useState('mapa')
  const Actual = TABS.find((t) => t[0] === tab)[2]
  return html`
    <header><h1>SENI·Sienna</h1><span class="sub">Recreación del SENI en Sienna/NREL — operación, dinámica y despacho</span></header>
    <nav>${TABS.map(([id, l]) => html`<button key=${id} class=${tab === id ? 'act' : ''} onClick=${() => setTab(id)}>${l}</button>`)}</nav>
    <main><${Actual} /></main>`
}

render(html`<${App} />`, document.getElementById('root'))
