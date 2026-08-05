import { render } from 'preact'
import { useState, useEffect, useRef } from 'preact/hooks'
import { html } from 'htm/preact'
import * as L from 'leaflet'
import katex from 'katex'

// ------------------------------------------------------------------ API ----
const j = async (u, o) => { const r = await fetch(u, o); if (!r.ok) throw new Error(`${u} ${r.status}`); return r.json() }
const api = {
  corridas: () => j('/api/corridas'), lanzar: (id) => j(`/api/corridas/${id}`, { method: 'POST' }),
  log: (id) => j(`/api/log/${id}`), resultados: () => j('/api/resultados'),
  tabla: (n) => j(`/api/tabla/${encodeURIComponent(n)}`), doc: (n) => j(`/api/doc/${encodeURIComponent(n)}`),
  generadores: () => j('/api/generadores'), escenario: () => j('/api/escenario'),
  correrEscenario: (b) => j('/api/escenario', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b) }),
  feedOc: () => j('/api/feed_oc'), mapa: (c) => j(`/api/mapa?capa=${c || 'kv'}`), red: () => j('/api/red'),
  serie: (t) => j(`/api/serie/${t}`), kpis: () => j('/api/kpis'), mapaHora: () => j('/api/mapa_hora'),
  validacionOc: () => j('/api/validacion_oc'),
}
const fig = (n) => `/figuras/${n}`
const K = (tex) => { try { return katex.renderToString(tex, { displayMode: true, output: 'html', throwOnError: false }) } catch (e) { return '<code>' + tex + '</code>' } }
const COL = { term: '#94a3b8', hidro: '#2563eb', renov: '#22c55e', ink: '#0f172a', acc: '#2563eb', bad: '#e74c3c', warn: '#f59e0b', line: '#e6e8ec', mut: '#64748b' }
// paleta de combustible idéntica a modom-pypsa (dashboard.py FUEL_COLORS)
const FUEL_COLORS = { 'Solar': '#f4c430', 'Eólica': '#33c9b8', 'Hidro': '#3b9ae1', 'Gas Natural': '#f08a24',
  'Fuel Oil / Diesel': '#b0683c', 'Carbón': '#6b6f76', 'Biomasa': '#5cb85c', 'Otra': '#9b7fd4' }

// ------------------------------------------------------------ Plot (Plotly) --
const BASE_LAYOUT = {
  margin: { l: 50, r: 18, t: 30, b: 42 }, font: { family: 'system-ui,Segoe UI,sans-serif', size: 12, color: COL.ink },
  paper_bgcolor: 'white', plot_bgcolor: 'white', legend: { orientation: 'h', y: -0.18, font: { size: 11 } },
  xaxis: { gridcolor: '#eef1f5', zeroline: false }, yaxis: { gridcolor: '#eef1f5', zeroline: false },
}
function Plot({ data, layout, height = 340 }) {
  const el = useRef(null)
  useEffect(() => {
    if (!el.current || !window.Plotly) return
    const lay = { ...BASE_LAYOUT, ...layout, height,
      xaxis: { ...BASE_LAYOUT.xaxis, ...(layout?.xaxis || {}) }, yaxis: { ...BASE_LAYOUT.yaxis, ...(layout?.yaxis || {}) } }
    window.Plotly.react(el.current, data || [], lay, { displayModeBar: false, responsive: true })
  }, [data, layout, height])
  useEffect(() => () => { el.current && window.Plotly && window.Plotly.purge(el.current) }, [])
  return html`<div ref=${el} style=${{ width: '100%', height: height + 'px' }}></div>`
}
const card = (titulo, sub, cuerpo) => html`<div class="card"><div class="cardhd"><h3>${titulo}</h3>${sub && html`<span class="sub">${sub}</span>`}</div>${cuerpo}</div>`

// -------------------------------------------------------------- markdown ----
function renderMd(s) {
  s = s.replace(/&/g, '&amp;').replace(/</g, '&lt;'); const out = []; let t = false
  for (let ln of s.split('\n')) {
    if (/^\|/.test(ln)) {
      if (/^\|[\s\-|:]+\|$/.test(ln.trim())) continue
      const c = ln.split('|').slice(1, -1).map((x) => x.trim())
      if (!t) { out.push('<table>'); t = true; out.push('<tr>' + c.map((x) => `<th>${x}</th>`).join('') + '</tr>') }
      else out.push('<tr>' + c.map((x) => `<td>${x}</td>`).join('') + '</tr>'); continue
    } else if (t) { out.push('</table>'); t = false }
    ln = ln.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/`([^`]+)`/g, '<code>$1</code>').replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1')
    if (/^### /.test(ln)) out.push('<h3>' + ln.slice(4) + '</h3>')
    else if (/^## /.test(ln)) out.push('<h2>' + ln.slice(3) + '</h2>')
    else if (/^# /.test(ln)) out.push('<h2>' + ln.slice(2) + '</h2>')
    else if (/^- /.test(ln)) out.push('<li>' + ln.slice(2) + '</li>')
    else if (/^> /.test(ln)) out.push('<p style="color:var(--muted);border-left:3px solid var(--line);padding-left:10px">' + ln.slice(2) + '</p>')
    else if (ln.trim() === '---') out.push('<hr>')
    else out.push(ln.trim() === '' ? '' : '<p>' + ln + '</p>')
  }
  if (t) out.push('</table>'); return out.join('\n')
}

// ------------------------------------------------------------- Operación ----
// orden de apilado: base firme abajo (carbón) → variable arriba (solar)
const FUEL_STACK = ['Carbón', 'Fuel Oil / Diesel', 'Gas Natural', 'Biomasa', 'Hidro', 'Eólica', 'Solar', 'Otra']
function MixHorario({ height = 340 }) {
  const [d, setD] = useState(null); useEffect(() => { api.serie('despacho_tec').then(setD).catch(() => {}) }, [])
  if (!d || !d.horas?.length || !d.series) return html`<div class="vacio">Ejecuta <b>Despacho ED</b> para ver el mix horario.</div>`
  const byName = Object.fromEntries(d.series.map((s) => [s.nombre, s.mw]))
  const orden = FUEL_STACK.filter((f) => byName[f])
  const data = orden.map((f) => ({ x: d.horas, y: byName[f], name: f, stackgroup: 'g', mode: 'none',
    fillcolor: FUEL_COLORS[f], hovertemplate: `${f}: %{y:.0f} MW<extra></extra>` }))
  data.push({ x: d.horas, y: d.demanda, name: 'Demanda', mode: 'lines', line: { color: COL.ink, dash: 'dot', width: 2 }, hovertemplate: 'Demanda: %{y:.0f} MW<extra></extra>' })
  return html`<${Plot} data=${data} height=${height} layout=${{ xaxis: { title: 'Hora', dtick: 2 }, yaxis: { title: 'MW' }, legend: { orientation: 'h', y: -0.22, font: { size: 10.5 } } }} />`
}
function CommitmentHeatmap({ height = 420 }) {
  const [d, setD] = useState(null); useEffect(() => { api.serie('commitment').then(setD).catch(() => {}) }, [])
  if (!d || !d.unidades?.length) return html`<div class="vacio">Ejecuta <b>UC MILP</b> para ver el commitment.</div>`
  const data = [{ z: d.matriz, x: d.horas, y: d.unidades, type: 'heatmap', xgap: 1, ygap: 1,
    colorscale: [[0, '#eef1f5'], [1, COL.acc]], showscale: false, hovertemplate: 'u %{y}<br/>h %{x}: %{z}<extra></extra>' }]
  return html`<${Plot} data=${data} height=${height} layout=${{ xaxis: { title: 'Hora', dtick: 2 }, yaxis: { automargin: true, tickfont: { size: 9 } } }} />`
}
function Kpis() {
  const [k, setK] = useState([]); useEffect(() => { api.kpis().then((r) => setK(r.kpis || [])).catch(() => {}) }, [])
  return html`<div class="kpis">${k.map((x) => html`<div class="kpi" key=${x.k}><div class="v">${x.v}</div><div class="l">${x.k}</div></div>`)}</div>`
}
function Operacion() {
  return html`
    <${Kpis} />
    <div class="cols2">
      ${card('Despacho por tecnología', 'despacho ED — mix por combustible vs demanda (24 h)', html`<${MixHorario} />`)}
      ${card('Compromiso de unidades (commitment)', 'UC MILP — encendido/apagado por unidad y hora', html`<${CommitmentHeatmap} />`)}
    </div>`
}

// ------------------------------------------------------------- Despacho -----
function DespachoUnidad({ height = 460 }) {
  const [d, setD] = useState(null); useEffect(() => { api.serie('despacho_unidad').then(setD).catch(() => {}) }, [])
  if (!d || !d.unidades?.length) return html`<div class="vacio">Ejecuta <b>Despacho ED</b>.</div>`
  const data = d.unidades.map((u, i) => ({ x: d.horas, y: d.series[i], name: u, mode: 'lines', line: { width: 1.4 },
    hovertemplate: `<b>${u}</b><br>h %{x}: %{y:.0f} MW<extra></extra>` }))
  return html`<${Plot} data=${data} height=${height} layout=${{ xaxis: { title: 'Hora', dtick: 2 }, yaxis: { title: 'MW' }, legend: { orientation: 'h', y: -0.14, font: { size: 9.5 } } }} />`
}
function EnvolventeTension({ height = 340 }) {
  const [d, setD] = useState(null); useEffect(() => { api.serie('tension').then(setD).catch(() => {}) }, [])
  if (!d || !d.horas?.length) return html`<div class="vacio">Ejecuta <b>Cuasi-dinámico 24h</b>.</div>`
  const band = (y, c) => ({ x: d.horas, y: Array(d.horas.length).fill(y), mode: 'lines', line: { color: COL.bad, dash: 'dash', width: 1 }, showlegend: false, hoverinfo: 'skip' })
  const data = [
    { x: d.horas, y: d.v_max, name: 'V máx', mode: 'lines', line: { color: COL.hidro, width: 2 } },
    { x: d.horas, y: d.v_min, name: 'V mín', mode: 'lines', line: { color: COL.bad, width: 2 } },
    band(1.05), band(0.95)]
  return html`<${Plot} data=${data} height=${height} layout=${{ xaxis: { title: 'Hora', dtick: 2 }, yaxis: { title: 'Tensión (pu)' } }} />`
}
function Despacho() {
  return html`
    ${card('Despacho por central (todas) por hora', 'LP de despacho económico — MW por central térmica, por nombre', html`<${DespachoUnidad} />`)}
    <div class="cols2" style="margin-top:13px">
      ${card('Mix por tecnología', 'estructura horaria por combustible (modom-pypsa)', html`<${MixHorario} height=${320} />`)}
      ${card('Envolvente de tensión 24h', 'cuasi-dinámico — banda 0.95–1.05 pu', html`<${EnvolventeTension} height=${320} />`)}
    </div>`
}

// ------------------------------------------------------------- Dinámica -----
function Frecuencia({ height = 360 }) {
  const [d, setD] = useState(null); useEffect(() => { api.serie('frecuencia').then(setD).catch(() => {}) }, [])
  if (!d || !d.series || !Object.keys(d.series).length) return html`<div class="vacio">Ejecuta <b>Deslastre selectivo</b> o <b>EDAC</b>.</div>`
  const et = { sin: ['Sin EDAC', COL.mut], edac: ['EDAC actual', COL.bad], sel: ['Selectivo', COL.acc] }
  const data = Object.entries(d.series).map(([k, pts]) => ({ x: pts.map((p) => p[0]), y: pts.map((p) => p[1]),
    name: et[k]?.[0] || k, mode: 'lines', line: { color: et[k]?.[1], width: 2 } }))
  data.push({ x: [0, 30], y: [59.2, 59.2], mode: 'lines', name: 'Criterio 59.2 Hz', line: { color: COL.warn, dash: 'dash', width: 1 } })
  return html`<${Plot} data=${data} height=${height} layout=${{ xaxis: { title: 'Tiempo (s)', range: [0, 12] }, yaxis: { title: 'Frecuencia (Hz)' } }} />`
}
function PequenaSenal({ height = 340 }) {
  const [d, setD] = useState(null); useEffect(() => { api.serie('pequena').then(setD).catch(() => {}) }, [])
  if (!d || !d.modos?.length) return html`<div class="vacio">Ejecuta <b>Pequeña señal</b>.</div>`
  const crit = d.modos.filter((m) => m.z < 10), ok = d.modos.filter((m) => m.z >= 10)
  const pts = (a, c, n) => ({ x: a.map((m) => m.f), y: a.map((m) => m.z), mode: 'markers', name: n, marker: { color: c, size: 7, opacity: 0.8 } })
  const data = [pts(ok, COL.hidro, 'ζ ≥ 10%'), pts(crit, COL.bad, 'ζ < 10%'),
    { x: [0.1, 3], y: [10, 10], mode: 'lines', name: 'umbral 10%', line: { color: COL.warn, dash: 'dash', width: 1 } }]
  return html`<${Plot} data=${data} height=${height} layout=${{ xaxis: { title: 'Frecuencia del modo (Hz)' }, yaxis: { title: 'Amortiguamiento ζ (%)' } }} />`
}
function N1Ranking({ height = 360 }) {
  const [d, setD] = useState(null); useEffect(() => { api.serie('n1').then(setD).catch(() => {}) }, [])
  if (!d || !d.items?.length) return html`<div class="vacio">Ejecuta <b>Contingencias N-1</b>.</div>`
  const it = [...d.items].reverse()
  const data = [{ x: it.map((i) => i.n), y: it.map((i) => i.c), type: 'bar', orientation: 'h', marker: { color: COL.acc } }]
  return html`<${Plot} data=${data} height=${height} layout=${{ xaxis: { title: 'Sobrecargas nuevas (DC)' }, yaxis: { automargin: true, tickfont: { size: 10 } } }} />`
}
function Dinamica() {
  return html`
    ${card('Respuesta de frecuencia — pérdida de Punta Catalina 2 (360 MW)', 'sin EDAC vs EDAC actual (502 MW) vs selectivo (150 MW)', html`<${Frecuencia} />`)}
    <div class="cols2" style="margin-top:13px">
      ${card('Pequeña señal — modos electromecánicos', 'amortiguamiento vs frecuencia (0.1–3 Hz)', html`<${PequenaSenal} />`)}
      ${card('Contingencias N-1 críticas', 'sobrecargas nuevas por contingencia', html`<${N1Ranking} />`)}
    </div>`
}

// ----------------------------------------------------------------- Mapa -----
const nivelColor = (kv) => kv >= 230 ? '#e74c3c' : kv >= 138 ? '#2e86ff' : kv >= 69 ? '#2ecc71' : '#8aa0b4'
function heatV(v) {
  if (v == null) return '#5a6b7d'
  const lo = 0.93, mid = 1.0, hi = 1.07
  const lerp = (a, b, t) => a.map((x, i) => Math.round(x + (b[i] - x) * t))
  const hex = (c) => '#' + c.map((x) => Math.max(0, Math.min(255, x)).toString(16).padStart(2, '0')).join('')
  const azul = [46, 134, 255], blanco = [240, 240, 240], naranja = [243, 156, 18], rojo = [231, 76, 60]
  if (v <= mid) return hex(lerp(azul, blanco, Math.pow(Math.max(0, (v - lo) / (mid - lo)), 1.6)))
  const t = Math.min(1, (v - mid) / (hi - mid)); return hex(t < 0.6 ? lerp(blanco, naranja, t / 0.6) : lerp(naranja, rojo, (t - 0.6) / 0.4))
}
const CAPAS = [['kv', 'Nivel de tensión'], ['vpu', 'Tensión del flujo (pu)'], ['vhora', 'Tensión por hora (24h)'], ['edac', 'Deslastre EDAC']]
const LEY_V = [['#2e86ff', '≤ 0.95 pu'], ['#f0f0f0', '≈ 1.00 pu'], ['#f39c12', '1.04 pu'], ['#e74c3c', '≥ 1.07 pu'], ['#5a6b7d', 'sin dato']]
const LEY = {
  kv: [['#e74c3c', '≥ 230 kV'], ['#2e86ff', '138 kV'], ['#2ecc71', '69 kV'], ['#8aa0b4', 'otros']],
  vpu: LEY_V, vhora: LEY_V,
  edac: [['#a06bff', 'alimentador EDAC'], ['#33506b', 'sin deslastre']],
}
function Mapa() {
  const [capa, setCapa] = useState('kv'); const [datos, setDatos] = useState(null); const [verLineas, setVerLineas] = useState(true)
  const [hora, setHora] = useState(20); const [vhora, setVhora] = useState(null)
  const el = useRef(null), map = useRef(null), lg = useRef(null), lgLine = useRef(null), red = useRef(null)
  useEffect(() => {
    const m = L.map(el.current, { preferCanvas: true }).setView([18.9, -70.5], 8)
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
      { attribution: '© OpenStreetMap © CARTO', maxZoom: 19, subdomains: 'abcd' }).addTo(m)
    map.current = m; lgLine.current = L.layerGroup().addTo(m); lg.current = L.layerGroup().addTo(m)
    api.red().then((r) => { red.current = r.segmentos; dibujaLineas() }).catch(() => {})
    return () => m.remove()
  }, [])
  const dibujaLineas = () => {
    if (!lgLine.current) return; lgLine.current.clearLayers()
    if (!verLineas || !red.current) return
    for (const s of red.current) {
      const c = s.tipo === 'transformer' ? '#8aa0b4' : nivelColor(s.kv)
      L.polyline([s.from, s.to], { color: c, weight: s.kv >= 230 ? 2 : s.kv >= 138 ? 1.4 : 0.9, opacity: 0.55 })
        .bindTooltip(`${s.nombre} · ${s.kv} kV`).addTo(lgLine.current)
    }
  }
  useEffect(() => { dibujaLineas() }, [verLineas])
  useEffect(() => { api.mapa(capa === 'vhora' ? 'kv' : capa).then(setDatos).catch(() => {}) }, [capa])
  useEffect(() => { if (capa === 'vhora' && !vhora) api.mapaHora().then(setVhora).catch(() => {}) }, [capa])
  useEffect(() => {
    if (!lg.current || !datos) return
    const vh = capa === 'vhora' && vhora ? vhora.por_barra : null
    lg.current.clearLayers()
    for (const b of datos.barras) {
      let col, rad = b.kv >= 230 ? 6 : b.kv >= 138 ? 4.5 : 3.4
      const vha = vh ? (vh[b.id] || [])[hora - 1] : null
      if (capa === 'vpu') { col = heatV(b.vpu); if (b.vpu != null) rad += 0.6 }
      else if (capa === 'vhora') { col = heatV(vha); if (vha != null) rad += 0.6 }
      else if (capa === 'edac') { col = b.edac_mw > 0 ? '#a06bff' : '#33506b'; rad = b.edac_mw > 0 ? 6 + Math.min(b.edac_mw / 20, 12) : 2.4 }
      else col = nivelColor(b.kv)
      let tip = `<b>${b.nombre}</b> (${b.id})<br/>${b.kv} kV`
      if (capa === 'vpu' && b.vpu != null) tip += `<br/>V = ${b.vpu.toFixed(3)} pu`
      if (capa === 'vhora' && vha != null) tip += `<br/>h${hora}: V = ${vha.toFixed(3)} pu`
      if (capa === 'edac' && b.edac_mw > 0) tip += `<br/>EDAC: ${b.edac_mw.toFixed(1)} MW`
      L.circleMarker([b.lat, b.lon], { radius: rad, color: 'rgba(255,255,255,.4)', fillColor: col, fillOpacity: 0.92, weight: 0.8 })
        .bindTooltip(tip).addTo(lg.current)
    }
  }, [datos, capa, hora, vhora])
  return html`
    <div class="mapwrap">
      <div class="legend">
        <div class="capsel"><h4>Capa</h4>
          ${CAPAS.map(([id, l]) => html`<label key=${id}><input type="radio" checked=${capa === id} onChange=${() => setCapa(id)} /> ${l}</label>`)}
        </div>
        <label style="display:flex;gap:7px;font-size:13px;margin-bottom:12px;cursor:pointer">
          <input type="checkbox" checked=${verLineas} onChange=${(e) => setVerLineas(e.target.checked)} /> Líneas de transmisión</label>
        ${capa === 'vhora' && html`<div style="margin-bottom:12px">
          <h4>Hora: ${hora}:00</h4>
          <input type="range" min="1" max="24" step="1" value=${hora} style="width:100%" onInput=${(e) => setHora(+e.target.value)} />
          <div style="font-size:11.5px;color:var(--muted)">arrastra para ver la tensión hora a hora (cuasi-dinámico)</div></div>`}
        <h4>Leyenda</h4>
        ${LEY[capa].map(([c, l]) => html`<div class="li" key=${l}><span class="dot" style=${{ background: c }}></span> ${l}</div>`)}
        <div style="margin-top:14px;font-size:12px;color:var(--muted)">${datos?.barras.length ?? 0} barras · ${red.current?.length ?? 0} ramas</div>
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
  useEffect(() => { if (!sel) return; const f = () => api.log(sel).then((r) => setLog(r.texto || '(log vacío)')); f(); const iv = setInterval(f, 3000); return () => clearInterval(iv) }, [sel])
  const lanzar = async (id) => { await api.lanzar(id); setSel(id) }
  return html`
    <div class="grid">
      ${cs.map((c) => html`<div class="card" key=${c.id}><h3>${c.nombre}</h3><div class="d">${c.desc}</div>
        <div class="fila"><span class="badge ${c.estado}">${c.estado}</span>
          <span style="color:var(--muted);font-size:11.5px">${c.script}</span>
          <button class="run" disabled=${c.estado === 'corriendo'} onClick=${() => lanzar(c.id)}>Ejecutar</button></div></div>`)}
    </div>
    <div class="sec">Log de la corrida</div>
    <select value=${sel} onChange=${(e) => setSel(e.target.value)}>${cs.map((c) => html`<option value=${c.id} key=${c.id}>${c.nombre}</option>`)}</select>
    <pre class="log">${log}</pre>`
}

// ------------------------------------------------------------- Escenario ----
function CurvaEscenario({ base, esc, height = 380 }) {
  if (!base?.length) return html`<div class="vacio">Ejecuta un escenario para ver el despacho térmico horario.</div>`
  const horas = base.map((_, i) => i + 1)
  const data = [{ x: horas, y: base, name: 'Base', mode: 'lines', line: { color: COL.mut, dash: 'dash', width: 2 } }]
  if (esc?.length && esc.some((v, i) => Math.abs(v - base[i]) > 0.1))
    data.push({ x: horas, y: esc, name: 'Escenario', mode: 'lines', line: { color: COL.acc, width: 2.5 } })
  return html`<${Plot} data=${data} height=${height} layout=${{ xaxis: { title: 'Hora', dtick: 2 }, yaxis: { title: 'Generación térmica (MW)' } }} />`
}
function Escenario() {
  const [gens, setGens] = useState([]); const [ds, setDs] = useState(1.0); const [rp, setRp] = useState(3)
  const [dis, setDis] = useState([]); const [resumen, setResumen] = useState(null); const [log, setLog] = useState(''); const [run, setRun] = useState(false)
  const [curvaB, setCurvaB] = useState([]); const [curvaE, setCurvaE] = useState([])
  const refrescar = () => { api.escenario().then((r) => { setResumen(r.resumen); setCurvaB(r.curva_base || []); setCurvaE(r.curva_esc || []) }); api.log('escenario').then((r) => setLog(r.texto || '')) }
  useEffect(() => { api.generadores().then((r) => setGens(r.generadores || [])); refrescar() }, [])
  const toggle = (id) => setDis((d) => d.includes(id) ? d.filter((x) => x !== id) : [...d, id])
  const ejecutar = async () => {
    setRun(true); await api.correrEscenario({ demand_scale: ds, reserve_pct: rp / 100, gen_disabled: dis, cvp_mult: {} })
    const iv = setInterval(async () => { const cs = await api.corridas(); const e = cs.find((c) => c.id === 'escenario'); refrescar(); if (e && e.estado !== 'corriendo') { clearInterval(iv); setRun(false) } }, 3000)
  }
  return html`
    <div class="escgrid">
      <div class="card"><h3>Perillas del escenario</h3><div class="d">Corre un UC alternativo; se compara contra la línea base.</div>
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
        ${resumen ? html`<div class="scroll"><table><thead><tr>${resumen.columnas.map((c) => html`<th key=${c}>${c}</th>`)}</tr></thead>
            <tbody>${resumen.filas.map((f, i) => html`<tr key=${i}>${f.map((v, k) => html`<td key=${k}>${v}</td>`)}</tr>`)}</tbody></table></div>`
          : html`<div class="card">Ejecuta un escenario para ver el delta vs base.</div>`}
        <div class="card" style="margin-top:12px"><div class="cardhd"><h3>Despacho térmico horario</h3><span class="sub">base vs escenario</span></div>
          <${CurvaEscenario} base=${curvaB} esc=${curvaE} /></div>
        <pre class="log">${log || '(sin corridas de escenario)'}</pre>
      </div>
    </div>`
}

// --------------------------------------------------------------- Reporte ----
function Reporte() {
  const [docs, setDocs] = useState([]); const [sel, setSel] = useState(''); const [h, setH] = useState('')
  useEffect(() => { api.resultados().then((r) => { const p = 'REPORTE_SENI_SIENNA.md'; const o = [...r.docs.filter((d) => d === p), ...r.docs.filter((d) => d !== p)]; setDocs(o); if (o.length) setSel(o[0]) }) }, [])
  useEffect(() => { if (sel) api.doc(sel).then((r) => setH(renderMd(r.texto))) }, [sel])
  return html`<select value=${sel} onChange=${(e) => setSel(e.target.value)} style="margin-bottom:12px">${docs.map((d) => html`<option key=${d}>${d}</option>`)}</select>
    <div class="doc" dangerouslySetInnerHTML=${{ __html: h }}></div>`
}

// ----------------------------------------------------------------- Datos ----
function Datos() {
  const [f, setF] = useState(null); useEffect(() => { api.feedOc().then(setF) }, [])
  return html`<div class="card" style="max-width:820px"><h3>Procedencia de los datos</h3><div class="d">Origen de cada insumo (nada de esto se versiona en git).</div>
    <div class="scroll" style="margin-top:10px"><table><thead><tr><th>Insumo</th><th>Estado</th><th>Origen</th></tr></thead>
      <tbody>${f?.items.map((i) => html`<tr key=${i.nombre}><td>${i.nombre}</td><td style=${{ color: i.ok ? 'var(--good)' : 'var(--bad)' }}>${i.ok ? 'presente' : 'falta'}</td><td>${i.origen}</td></tr>`)}</tbody></table></div>
    ${f && html`<p style="margin-top:12px;font-size:13px;color:var(--muted)">Recurso OC: <a href=${f.recurso} target="_blank">${f.recurso}</a></p>`}</div>`
}

// ---------------------------------------------------------- Metodología ----
const S = String.raw
const EQS = [
  { n: 1, grp: 'Función objetivo', titulo: 'Costo total de operación', ref: '§6.1', cob: 'par',
    tex: S`\min Z=\sum_{n}\sum_{g\in G_t}CVP_g^{ef}P_{n,g}+CENS\sum_n PNS_n^{tot}+\sum_n\sum_e CVERR\,VERT_{n,e}+CVRRF\sum_n\sum_{g\in G_{RSF}}\xi_{n,g}^{RSF}+\sum_n\sum_{g\in G_t}(C_g^{ARR}u_{n,g}^{ARR}+C_g^{PAR}u_{n,g}^{PAR})`,
    dom: 'Térmica + déficit + vertimientos + reservas + arranque/parada.',
    sienna: 'ThermalGenerationCost: variable CVP lineal + start_up (estimado CVP·PMN·TARR) en el UC; ENS/vertido con costo CENS en el LP. Vertimiento renovable y embalses aún parciales.' },
  { n: 2, grp: '', titulo: 'Costo variable efectivo (NCV/OPLM)', ref: '§6.2', cob: 'si',
    tex: S`CVP_g^{ef}=\begin{cases}CVP_g,&\text{NCV}\\ \dfrac{CVP_g}{FNPROM_g},&\text{OPLM}\end{cases}`,
    sienna: 'Curva de costo lineal por unidad con el CVP declarado (VEROPE). El uplift OPLM por factor de nodo se aplica en el lazo DC↔AC de pérdidas.' },
  { n: 3, grp: '7.1 · Compromiso', titulo: 'Estados mutuamente excluyentes', ref: '§7.1.1', cob: 'par',
    tex: S`v_{n,g}^{ACC}+u_{n,g}^{ARR}\mathbf 1_{TARR_g\ge1}+u_{n,g}^{PAR}\mathbf 1_{TPAR_g\ge1}+v_{n,g}^{RFA}=1`,
    dom: 'ACC acoplada · ARR arrancando · PAR parando · RFA reserva fría.',
    sienna: 'ThermalStandardUnitCommitment: variable binaria on/off. Los 4 estados MODOM se colapsan a encendido/apagado + start/stop de PSI.' },
  { n: 4, grp: '', titulo: 'Transiciones de estado prohibidas', ref: '§7.1.2', cob: 'par',
    tex: S`u_{n-1,g}^{PAR}+v_{n,g}^{ACC}\le1,\quad u_{n-1,g}^{ARR}+u_{n,g}^{PAR}\le1,\quad v_{n-1,g}^{RFA}+v_{n,g}^{ACC}\le1,\ \dots`,
    sienna: 'Implícitas en las variables StartVariable/StopVariable de PSI (una unidad no arranca y para en el mismo paso).' },
  { n: 5, grp: '7.2 · Potencias variables', titulo: 'Potencia máxima variable', ref: '§7.2.1', cob: 'par',
    tex: S`PG_{n,g}^{MAX}=v_{n,g}^{ACC}PMX_{n,g}+\tfrac{PMN_{n,g}}{TARR_g}\!\!\sum_{t\in\mathcal T_{ARR}}\!\!(n^*+TARR_g-t^*)u_{t,g}^{ARR}+\dots`,
    sienna: 'La rampa de arranque de PSI aproxima la trayectoria; PSI no modela el techo PMX variable durante el arranque/parada.' },
  { n: 6, grp: '', titulo: 'Potencia mínima variable', ref: '§7.2.2', cob: 'par',
    tex: S`PG_{n,g}^{MIN}=v_{n,g}^{ACC}PMN_{n,g}+\tfrac{PMN_{n,g}}{TARR_g}\!\!\sum_{t\in\mathcal T_{ARR}}\!\!(n^*+TARR_g-t^*)u_{t,g}^{ARR}+\dots`,
    sienna: 'Igual que la máxima: aproximada por rampas de arranque; el piso variable no se modela explícitamente.' },
  { n: 7, grp: '7.3 · Límites de generación', titulo: 'Límite superior con márgenes', ref: '§7.3.1', cob: 'si',
    tex: S`P_{n,g}\le PG_{n,g}^{MAX}-MR_{n,g}^{AGC}-MR_{n,g}^{RSF}-(MR_{n,g}^{RPF}-SAE_{g,n})v_{n,g}^{ACC}`,
    sienna: 'active_power_limits.max × on, con headroom reservado por la co-optimización de reservas (RangeReserve descuenta el margen del despacho).' },
  { n: 8, grp: '', titulo: 'Límite inferior — centrales regulares', ref: '§7.3.2', cob: 'si',
    tex: S`P_{n,g}\ge PG_{n,g}^{MIN}+MR_{n,g}^{AGC}+MR_{n,g}^{RSF}+HSF_{g,n}v_{n,g}^{ACC}+(MR_{n,g}^{RPF}-SAE_{g,n})v_{n,g}^{ACC}`,
    sienna: 'pmin × on + margen de reserva hacia abajo. HSF (holgura RSF) no separada.' },
  { n: 9, grp: '', titulo: 'Límite inferior — autoproductores', ref: '§7.3.3', cob: 'par',
    tex: S`P_{n,g}\ge PFP_{g,n}+MR_{n,g}^{AGC}+MR_{n,g}^{RSF}+HSF_{g,n}v_{n,g}^{ACC}+(MR_{n,g}^{RPF}-SAE_{g,n})v_{n,g}^{ACC}`,
    sienna: 'Los autoproductores (PFP mínimo por contrato) no se distinguen; se usa el pmin estándar. Backlog.' },
  { n: 10, grp: '7.4 · Reserva del sistema', titulo: 'Requisito de RPF', ref: '§7.4.1', cob: 'si',
    tex: S`\sum_{g\in G_{RPF}}(MR_{n,g}^{RPF}+\xi_{n,g}^{RPF})\ge RRPF_n\sum_{g\in G_{act}}P_{n,g}`,
    sienna: 'VariableReserve{ReserveUp} "RPF" co-optimizada (RangeReserve), requisito = 3% de la demanda horaria (Art. 399). ξ = slack.' },
  { n: 11, grp: '', titulo: 'Requisito de RSF', ref: '§7.4.2', cob: 'si',
    tex: S`\sum_{g\in G_{RSF}}(MR_{n,g}^{RSF}+HSF_{g,n}v_{n,g}^{ACC}+\xi_{n,g}^{RSF})+\sum_{g\in G_{AGC}}MR_{n,g}^{AGC}=RRSF_n\sum_g P_{n,g}`,
    sienna: 'VariableReserve{ReserveUp} "RSF_AGC" co-optimizada. La secundaria es la RSF-AGC del MODOM (regulación+AGC = un producto 3%); sus 40 proveedores (MRSF>0) se confirmaron AGC-capaces con la extracción de gobernadores (Ronda 2 VM).' },
  { n: 12, grp: '7.5 · Margen por central', titulo: 'Margen — centrales regulares', ref: '§7.5.1', cob: 'par',
    tex: S`MR_{n,g}^{RSF}\le\min(MTSF_{g,n},MRSFU_g UND_{g,n},MRSF_g)v_{n,g}^{ACC}DRS_{g,n}-MR_{n,g}^{AGC}`,
    sienna: 'max_participation_factor limita la contribución de cada unidad a la reserva; los sub-límites MTSF/MRSFU/DRS no se desagregan.' },
  { n: 13, grp: '', titulo: 'Margen — autoproductores', ref: '§7.5.2', cob: 'par',
    tex: S`MR_{n,g}^{RSF}\le\min\!\Big(\tfrac{MX_{g,n}-(PFP_{g,n}+2MR_{n,g}^{RPF})}{2},MRSF_g\Big)DRS_{g,n}-MR_{n,g}^{AGC}`,
    sienna: 'Cubierto por el límite genérico de participación; sin el tratamiento especial de autoproductor.' },
  { n: 14, grp: '7.6 · Reserva de AGC', titulo: 'Requisito agregado de AGC', ref: '§7.6.1', cob: 'no',
    tex: S`\sum_{g\in G_{AGC}}(MR_{n,g}^{AGC}+\xi_{n,g}^{AGC})\ge RRSF_n\sum_{g\in G_{act}}P_{n,g}`,
    sienna: 'El AGC no se modela como servicio separado; su margen queda absorbido en la RSF. Backlog (tercer VariableReserve).' },
  { n: 15, grp: '', titulo: 'Límite de AGC por central', ref: '§7.6.2', cob: 'no',
    tex: S`MR_{n,g}^{AGC}\le AGC_{g,n}`,
    sienna: 'No modelado (sin servicio AGC separado).' },
  { n: 16, grp: '7.7 · Rampas', titulo: 'Rampa de subida', ref: '§7.7.1', cob: 'si',
    tex: S`P_{n+1,g}-P_{n,g}\le RS_g\,v_{n,g}^{ACCS}`,
    sienna: 'ramp_limits.up = RS/60 (pu base propia/min) donde MODOM declara RS>0.' },
  { n: 17, grp: '', titulo: 'Rampa de bajada', ref: '§7.7.2', cob: 'si',
    tex: S`P_{n-1,g}-P_{n,g}\le RB_g\,v_{n,g}^{ACCB}`,
    sienna: 'ramp_limits.down = RB/60 donde MODOM declara RB>0.' },
  { n: 18, grp: '', titulo: 'Exclusividad de dirección de rampa', ref: '§7.7.3', cob: 'si',
    tex: S`v_{n,g}^{ACCS}+v_{n,g}^{ACCB}\le1`,
    sienna: 'Implícito: la restricción de rampa de PSI acota |P(n+1)−P(n)| en ambos sentidos.' },
  { n: 19, grp: '7.8–7.11 · Tiempos y arranques', titulo: 'Tiempo mínimo de arranque', ref: '§7.8', cob: 'si',
    tex: S`\sum_{t\in\mathcal T_{vent}}u_{t,g}^{ARR2}=TARR_g\,u_{n,g}^{ARR}+\sum_{k=1}^{TARR_g-1}(TARR_g-k)(u_{n-k,g}^{ARR}+u_{n+k,g}^{ARR})`,
    sienna: 'time_limits.up (TMO, con TARR como respaldo cuando TMO viene vacío en el workbook).' },
  { n: 20, grp: '', titulo: 'Tiempo mínimo de parada', ref: '§7.9', cob: 'si',
    tex: S`\sum_{t\in\mathcal T_{vent}}u_{t,g}^{PAR2}=TPAR_g\,u_{n,g}^{PAR}+\sum_{k=1}^{TPAR_g}(TPAR_g-k)(u_{n-k,g}^{PAR}+u_{n+k,g}^{PAR})`,
    sienna: 'time_limits.down (TMPA).' },
  { n: 21, grp: '', titulo: 'Mínimo en reserva fría', ref: '§7.10.1', cob: 'no',
    tex: S`\sum_{t\in\mathcal T_{min}}v_{t,g}^{RFA}\ge(TMPA_g+TPAR_g+TARR_g-1)u_{n,g}^{PAR}`,
    sienna: 'El estado de reserva fría (RFA) no existe en PSI; se aproxima con el tiempo mínimo de parada.' },
  { n: 22, grp: '', titulo: 'Máximo en reserva fría', ref: '§7.10.2', cob: 'no',
    tex: S`\sum_{t\in\mathcal T_{max}}v_{t,g}^{RFA}\le TMXPA_g+TPAR_g+TARR_g-2`,
    sienna: 'Sin estado RFA. No modelado.' },
  { n: 23, grp: '', titulo: 'Arranques consecutivos', ref: '§7.11.1', cob: 'par',
    tex: S`\sum_{t\in\mathcal T_{vent}}u_{t,g}^{ARR}\le1`,
    sienna: 'Cubierto indirectamente por los tiempos mínimos up/down.' },
  { n: 24, grp: '', titulo: 'Número máximo de arranques', ref: '§7.11.2', cob: 'no',
    tex: S`\sum_{n\in N}u_{n,g}^{ARR}\le NAMX_g`,
    sienna: 'NAMX no restringido aún en PSI (Σ start ≤ NAMX es agregable como extra_functionality). Backlog.' },
  { n: 25, grp: '7.12 · Enclavamiento', titulo: 'Enclavamiento de generadores', ref: '§7.12', cob: 'no',
    tex: S`ENCLAV_{g,g'}(v_{n,g}^{ACC}+v_{n,g'}^{ACC})\le1`,
    sienna: 'Sin datos ENCLAV en la capa canónica. No modelado.' },
  { n: 26, grp: '7.13 · Flujo de potencia', titulo: 'Ley de flujo DC', ref: '§7.13.1', cob: 'si',
    tex: S`F_{\ell,n}=\frac{S^{BASE}}{X_\ell}(\theta_{ni,n}-\theta_{nf,n})`,
    sienna: 'Red DC por ángulos (LP, script 03) y PTDFPowerModel (UC). Idéntico a MODOM.' },
  { n: 27, grp: '', titulo: 'Límites térmicos de líneas', ref: '§7.13.2', cob: 'si',
    tex: S`-FLJMAX_\ell\le F_{\ell,n}\le FLJMAX_\ell`,
    sienna: 'StaticBranch con rating. Hallazgo: MODOM es transporte — sin límite por rama, solo flowgates (StaticBranchUnbounded en el UC).' },
  { n: 28, grp: '', titulo: 'Restricciones de flowgate', ref: '§7.13.3', cob: 'si',
    tex: S`\sum_{\ell\in\mathcal L_{fg}}F_{\ell,n}FGATE_{\ell,fg}\le FLGTMAX_{fg,n}+\varepsilon`,
    sienna: 'TransmissionInterface + ConstantMaxInterfaceFlow (fg1 ≤ 200 MW, fg2 ≤ 670 MW).' },
  { n: 29, grp: '7.14 · Pérdidas', titulo: 'Modelo incremental de pérdidas', ref: '§7.14.1', cob: 'par',
    tex: S`PERD_{\ell,n}^{LINEA}\ge S^{BASE}\tfrac{R_\ell}{X_\ell^2}(\Delta\theta_\ell^{ref})^2+2S^{BASE}\tfrac{R_\ell}{X_\ell^2}\Delta\theta_\ell^{ref}[(\theta_{ni}-\theta_{nf})-\Delta\theta_\ell^{ref}]`,
    sienna: 'Lazo iterativo DC↔AC: PowerFlows (AC) → factores de pérdidas nodales → re-despacho, en vez de la linealización por rama.' },
  { n: 30, grp: '', titulo: 'Distribución de pérdidas por nodo', ref: '§7.14.2', cob: 'par',
    tex: S`PERD_{n,nd}=0.5\!\!\sum_{\ell:ni=nd}\!\!PERD_{\ell,n}^{LINEA}+0.5\!\!\sum_{\ell:nf=nd}\!\!PERD_{\ell,n}^{LINEA}`,
    sienna: 'Factor de pérdidas nodal aplicado como uplift a la demanda (lazo Layer 4).' },
  { n: 31, grp: '7.15–7.17 · Balance', titulo: 'Balance de potencia nodal', ref: '§7.15', cob: 'si',
    tex: S`\sum_{g\in G_{nd}}P_{n,g}+\!\!\sum_{\ell:nf=nd}\!\!F_{n,\ell}+PNS_{n,nd}=D_{n,nd}+\!\!\sum_{\ell:ni=nd}\!\!F_{n,\ell}+\sum_{g\in G_{nd}}SSA_{n,g}+PERD_{n,nd}`,
    sienna: 'Balance nodal (KCL) del NetworkModel de PSI con slack de ENS.' },
  { n: 32, grp: '', titulo: 'Potencia no suministrada total', ref: '§7.16', cob: 'si',
    tex: S`PNS_n^{tot}=\sum_{nd\in\mathcal{ND}}PNS_{n,nd}`,
    sienna: 'Slack de energía no suministrada por barra, penalizado con CENS.' },
  { n: 33, grp: '', titulo: 'Servicios auxiliares', ref: '§7.17', cob: 'par',
    tex: S`SSA_{n,g}=PMX_{n,g}\,SSAA_g`,
    sienna: 'El consumo de auxiliares (SSAA) se descuenta de la capacidad efectiva; no como carga separada por barra.' },
  { n: 34, grp: '7.18 · Embalses', titulo: 'Balance hídrico del embalse', ref: '§7.18.1', cob: 'par',
    tex: S`NEMB_{n,e}=NEMB_{n-1,e}+APORT_{n,e}-EXTR_{n,e}+APORT\_AA_{n,e}-VERT_{n,e}-\!\!\sum_{h\in\mathcal H_e}\!\!(1-SSAA_h)P_{n,h}\tfrac1{\eta_h}`,
    sienna: 'HydroDispatchRunOfRiver con techo de disponibilidad horaria; el balance de volumen del embalse (StorageSystemsSimulations) es el refinamiento pendiente.' },
  { n: 35, grp: '', titulo: 'Aportaciones desde aguas arriba', ref: '§7.18.2', cob: 'no',
    tex: S`APORT\_AA_{n,e}=\sum_{e'\in\mathcal E_{sup}}\sum_{h\in\mathcal H_{e'}}(1-SSAA_h)P_{n,h}\tfrac1{\eta_h}REST_{e,e'}+\sum_{e'}VERT_{n,e'}REST_{e,e'}`,
    sienna: 'Cascada hidráulica no modelada (sin acoplar embalses en serie). Backlog.' },
  { n: 36, grp: '', titulo: 'Límite de generación acumulada', ref: '§7.18.3', cob: 'no',
    tex: S`\sum_{n\in N}\sum_{h\in\mathcal H_e}P_{n,h}\le N\_INI_e`,
    sienna: 'Sin presupuesto de energía por embalse (requiere el reservorio explícito). Backlog.' },
  { n: 37, grp: 'Verificación eléctrica', titulo: 'Flujo AC (DIgSILENT/PowerFactory)', ref: '§8.3', cob: 'si',
    tex: S`P_i=\sum_j|V_i||V_j|(G_{ij}\cos\theta_{ij}+B_{ij}\sin\theta_{ij}),\quad Q_i=\sum_j|V_i||V_j|(G_{ij}\sin\theta_{ij}-B_{ij}\cos\theta_{ij})`,
    sienna: 'PowerFlows.jl (Newton-Raphson AC) sobre el System físico: |ΔV| medio 0.006 pu vs PowerFactory (P20 + control secundario + límites de Q).' },
]
const EqRow = ({ e }) => {
  const pill = { si: 'Implementada', par: 'Parcial', no: 'No / gap' }[e.cob]
  return html`<div class="eqrow">
    <div class="modom">
      ${e.grp && html`<div class="grp">${e.grp}</div>`}
      <div><span class="num">${e.n}</span><span class="titulo">${e.titulo}</span> <span class="ref">${e.ref}</span></div>
      <div class="eq" dangerouslySetInnerHTML=${{ __html: K(e.tex) }}></div>
      ${e.dom && html`<div class="dom">${e.dom}</div>`}
    </div>
    <div class="sienna"><div style="margin-bottom:5px"><b>Sienna</b> <span class="pill ${e.cob}">${pill}</span></div>${e.sienna}</div>
  </div>`
}
function Metodologia() {
  const n = (c) => EQS.filter((e) => e.cob === c).length
  return html`<div>
    <p style="color:var(--muted);max-width:920px">Las <b>37 ecuaciones</b> del MODOM (modelo oficial del OC: GAMS + DIgSILENT, transcripción V16), numeradas tal como aparecen en el documento, con <b>el abordaje de Sienna al lado de cada una</b>. Cobertura:
      <span class="pill si">Implementada ${n('si')}</span> <span class="pill par">Parcial ${n('par')}</span> <span class="pill no">No / gap ${n('no')}</span></p>
    ${EQS.map((e) => html`<${EqRow} e=${e} key=${e.n} />`)}
    <div class="card" style="margin-top:20px;max-width:1000px">
      <h3>Cómo se incorpora al software</h3>
      <p style="font-size:12.5px;line-height:1.7">
        <b>1 · Ingesta</b> del export PowerFactory + tablas MODOM → capa canónica (<code>src/parse_powerfactory.jl</code>, <code>build_modom_system.jl</code>).<br/>
        <b>2 · System PSY</b>: 717 barras (despacho) / 718 nodos (físico), generadores, reservas y flowgates.<br/>
        <b>3 · Escenario</b>: las perillas del usuario se aplican como <i>overrides</i> antes de resolver.<br/>
        <b>4 · Optimización</b> (PowerSimulations + HiGHS): <code>EconomicDispatch</code> / <code>ThermalStandardUnitCommitment</code> con reservas y flowgates.<br/>
        <b>5 · Verificación AC</b> (<code>PowerFlows.jl</code>) sobre el System físico — el paso que el OC hace en DIgSILENT.<br/>
        <b>6 · Dinámica</b> (<code>PowerSimulationsDynamics.jl</code>): pequeña señal y frecuencia con los modelos DSL reales.
      </p>
    </div>
  </div>`
}

// ------------------------------------------------------------------ App -----
const IC = (p) => html`<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" dangerouslySetInnerHTML=${{ __html: p }}></svg>`
// ------------------------------------------------------------ Validación OC --
function OcArea({ hora, titulo, height = 300 }) {
  const orden = FUEL_STACK.filter((f) => hora[f])
  const data = orden.map((f) => ({ x: [...Array(24).keys()].map((i) => i + 1), y: hora[f], name: f,
    stackgroup: 'g', mode: 'none', fillcolor: FUEL_COLORS[f], hovertemplate: `${f}: %{y:.0f} MW<extra></extra>` }))
  return html`<div><div class="sub" style="text-align:center;margin-bottom:4px">${titulo}</div>
    <${Plot} data=${data} height=${height} layout=${{ margin: { l: 46, r: 10, t: 8, b: 30 }, xaxis: { dtick: 3 }, yaxis: { title: 'MW' } }} /></div>`
}
function ValidacionOc() {
  const [d, setD] = useState(null); const [err, setErr] = useState(false)
  useEffect(() => { api.validacionOc().then(setD).catch(() => setErr(true)) }, [])
  if (err) return html`<div class="vacio">No se pudo consultar la API del OC.</div>`
  if (!d) return html`<div class="vacio">Cargando validación…</div>`
  if (d.disponible === false) return html`<div class="vacio">Ejecuta <b>Validación vs OC (API)</b> en Corridas para generar la comparación.</div>`
  const kpi = (k, v, c) => html`<div class="kpi"><div class="v" style=${c ? { color: c } : {}}>${v}</div><div class="l">${k}</div></div>`
  const dcol = (p) => Math.abs(p) < 12 ? COL.renov : Math.abs(p) < 40 ? COL.warn : COL.bad
  const gx = d.grupo.map((g) => g.grupo)
  const barra = [
    { x: gx, y: d.grupo.map((g) => g.oc_GWh), name: 'OC (real)', type: 'bar', marker: { color: '#2563eb' } },
    { x: gx, y: d.grupo.map((g) => g.sienna_GWh), name: 'Sienna', type: 'bar', marker: { color: '#f08a24' } },
  ]
  return html`
    <div class="grid">
      ${card('Validación contra el despacho real del OC', `${d.fecha} · ${d.fuente}`, html`
        <div class="kpis">
          ${kpi('Energía OC', d.oc_GWh + ' GWh')}
          ${kpi('Energía Sienna', d.sienna_GWh + ' GWh')}
          ${kpi('Δ total', (d.delta_total_pct > 0 ? '+' : '') + d.delta_total_pct + ' %', dcol(d.delta_total_pct))}
          ${kpi('R² horario', d.r2_horario)}
          ${kpi('Centrales OC', d.n_centrales)}
        </div>
        <p class="sub" style="margin-top:8px">Post-despacho del OC (misma fecha del modelo PDD) agregado por combustible y comparado con el despacho ED de Sienna. El corte por grupo coincide con los subtotales que publica el OC.</p>`)}
      ${card('Energía por grupo — OC vs Sienna', 'GWh/día', html`
        <${Plot} data=${barra} height=${320} layout=${{ barmode: 'group', yaxis: { title: 'GWh' } }} />`)}
      ${card('Mix horario — OC real vs Sienna', 'MW por hora', html`
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
          <${OcArea} hora=${d.oc_hora} titulo="OC (real)" />
          <${OcArea} hora=${d.sienna_hora} titulo="Sienna" />
        </div>`)}
      ${card('Detalle por combustible', 'GWh/día · Δ = Sienna − OC', html`
        <table><tr><th>Combustible</th><th>OC</th><th>Sienna</th><th>Δ %</th></tr>
        ${d.fuel.map((f) => html`<tr><td>${f.combustible}</td><td>${f.oc_GWh}</td><td>${f.sienna_GWh}</td>
          <td style=${{ color: dcol(f.delta_pct), fontWeight: 600 }}>${(f.delta_pct > 0 ? '+' : '') + f.delta_pct}</td></tr>`)}
        </table>
        <p class="sub" style="margin-top:8px">Eólica y fuel-oil se apartan porque el modelo usa perfiles renovables canónicos (no el clima del día) y prioriza gas sobre fuel-oil dual. Térmica/solar/hidro y la energía total coinciden dentro de ±10 %.</p>`)}
      ${d.central_top && card('Despacho por central — unidad × hora', 'matcheo directo por nombre (MODOM)', html`
        <div class="kpis">
          ${kpi('Unidades', d.n_central)}
          ${kpi('R² unidad×hora', d.r2_central)}
          ${kpi('MAE', d.mae_central + ' MW')}
        </div>
        <table style="margin-top:10px"><tr><th>Central</th><th>OC</th><th>Sienna</th><th>Δ GWh</th></tr>
        ${d.central_top.map((c) => html`<tr><td>${c.central}</td><td>${c.oc_GWh}</td><td>${c.sienna_GWh}</td>
          <td style=${{ color: dcol(100 * c.delta_GWh / (c.oc_GWh || 1)), fontWeight: 600 }}>${(c.delta_GWh > 0 ? '+' : '') + c.delta_GWh}</td></tr>`)}
        </table>
        <p class="sub" style="margin-top:8px">Mayores diferencias por unidad. Los pares como <b>Quisqueya 2 FO ↔ GN</b> (misma planta, MWh casi iguales, modo de combustible opuesto) confirman que el despacho es correcto y la diferencia está en el combustible declarado.</p>`)}
      ${d.serie && d.serie.length > 1 && (() => {
        const fx = d.serie.map((s) => s.fecha.slice(5))
        const r2avg = (d.serie.reduce((a, s) => a + (s.r2_central || 0), 0) / d.serie.length).toFixed(3)
        const data = [
          { x: fx, y: d.serie.map((s) => s.oc_GWh), name: 'OC energía', type: 'bar', marker: { color: '#c7d7ef' }, yaxis: 'y2', hovertemplate: 'OC %{y:.1f} GWh<extra></extra>' },
          { x: fx, y: d.serie.map((s) => s.r2_central), name: 'R² central', mode: 'lines+markers', line: { color: '#2563eb', width: 2 }, marker: { size: 6 }, hovertemplate: 'R² %{y:.3f}<extra></extra>' },
        ]
        return card('Barrido multi-día — representatividad del día canónico', `R²(central) medio ${r2avg} · 14 días`, html`
          <${Plot} data=${data} height=${330} layout=${{
            margin: { l: 46, r: 46, t: 10, b: 40 },
            yaxis: { title: 'R² central', range: [0, 1], side: 'left' },
            yaxis2: { title: 'GWh', overlaying: 'y', side: 'right', showgrid: false, rangemode: 'tozero' },
            xaxis: { tickangle: -45 } }} />
          <p class="sub" style="margin-top:8px">Sienna está fijo en el punto 30-09-2025; cada barra es un día real del OC. El R²(central) se mantiene ~0.70–0.80 en días laborables; los días de menor energía (fin de semana) bajan por la diferencia de demanda, no del modelo.</p>`)
      })()}
    </div>`
}

const TABS = [
  ['operacion', 'Operación', Operacion, '<path d="M3 3v18h18"/><path d="m7 14 4-4 3 3 5-6"/>'],
  ['mapa', 'Mapa', Mapa, '<path d="M9 3 3 5v16l6-2 6 2 6-2V3l-6 2-6-2Z"/><path d="M9 3v16M15 5v16"/>'],
  ['despacho', 'Despacho', Despacho, '<path d="M12 20V10"/><path d="M18 20V4"/><path d="M6 20v-4"/>'],
  ['dinamica', 'Dinámica', Dinamica, '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>'],
  ['escenario', 'Escenario', Escenario, '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-2.81 1.17V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.6 15H4.5a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 6 9.4l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 11 4.6V4.5a2 2 0 0 1 4 0v.09A1.65 1.65 0 0 0 18 6l.06-.06a2 2 0 1 1 2.83 2.83L20.83 9A1.65 1.65 0 0 0 21 11h-.09Z"/>'],
  ['valoc', 'Validación OC', ValidacionOc, '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/>'],
  ['metodologia', 'Metodología', Metodologia, '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2Z"/>'],
  ['corridas', 'Corridas', Corridas, '<circle cx="12" cy="12" r="10"/><polygon points="10 8 16 12 10 16 10 8"/>'],
  ['reporte', 'Reporte', Reporte, '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v5h5"/>'],
  ['datos', 'Datos', Datos, '<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14a9 3 0 0 0 18 0V5"/><path d="M3 12a9 3 0 0 0 18 0"/>'],
]
function App() {
  const [tab, setTab] = useState(location.hash.slice(1) || 'operacion')
  const cur = TABS.find((t) => t[0] === tab); const Actual = cur[2]
  return html`
    <div class="layout">
      <aside class="side">
        <div class="brand"><div class="logo">⚡</div><div><b>SENI·Sienna</b><small>NREL · República Dominicana</small></div></div>
        <nav class="nav">${TABS.map(([id, l, , p]) => html`<button key=${id} class=${tab === id ? 'act' : ''} onClick=${() => setTab(id)}>${IC(p)}${l}</button>`)}</nav>
        <div class="sidefoot">Recreación del SENI en Sienna — operación, despacho y dinámica por hora.</div>
      </aside>
      <div class="content">
        <div class="top"><h2>${cur[1]}</h2><span class="sub">Sistema Eléctrico Nacional Interconectado</span></div>
        <main><${Actual} /></main>
      </div>
    </div>`
}
render(html`<${App} />`, document.getElementById('root'))
