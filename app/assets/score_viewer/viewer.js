// Visor de partituras de Scale: Verovio dibuja el MusicXML que sirve la app
// y este script resalta notas, mueve el cursor y avisa de los toques.
'use strict';

(function () {
  const scoreEl = document.getElementById('score');
  const statusEl = document.getElementById('status');
  const cursorEl = document.getElementById('band');

  let tk = null;
  let lastUrl = null;
  let zoom = 45;
  /** id de Scale → elemento del SVG. */
  let byId = new Map();
  /** id del SVG → id de Scale (para los toques). */
  let toScale = new Map();
  let lit = [];

  // Puente con la app: en Android, el canal de webview_flutter (ScaleBridge);
  // en Windows, los manejadores de flutter_inappwebview.
  function send(name, data) {
    const payload = data === undefined ? null : data;
    try {
      if (window.ScaleBridge && window.ScaleBridge.postMessage) {
        window.ScaleBridge.postMessage(JSON.stringify({ name, data: payload }));
      } else if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler(name, payload);
      }
    } catch (e) { /* sin puente: abierto en un navegador */ }
  }

  function status(text) {
    statusEl.textContent = text || '';
    statusEl.style.display = text ? 'flex' : 'none';
  }

  function options() {
    const width = Math.max(320, document.documentElement.clientWidth);
    return {
      scale: zoom,
      pageWidth: Math.round(width * 100 / zoom),
      pageHeight: 60000,
      adjustPageHeight: true,
      breaks: 'auto',
      font: 'Bravura',
      header: 'auto',
      footer: 'none',
      pageMarginLeft: 40,
      pageMarginRight: 40,
      pageMarginTop: 30,
      pageMarginBottom: 30,
    };
  }

  /** Une las notas del SVG con las de Scale: por id si Verovio lo conservó; si
   * no, por posición en negras y altura MIDI. */
  function buildIndex(notes) {
    byId = new Map();
    toScale = new Map();
    let preserved = 0;
    const missing = [];
    for (const n of notes) {
      const el = document.getElementById(n.id);
      if (el) {
        byId.set(n.id, el);
        toScale.set(n.id, n.id);
        preserved++;
      } else {
        missing.push(n);
      }
    }
    let matched = 0;
    if (missing.length) {
      const pending = new Map();
      for (const n of missing) {
        const k = n.q.toFixed(3) + ':' + n.m;
        if (!pending.has(k)) pending.set(k, []);
        pending.get(k).push(n);
      }
      for (const entry of tk.renderToTimemap({ includeRests: false })) {
        for (const vid of entry.on || []) {
          const v = tk.getMIDIValuesForElement(vid);
          if (!v || v.pitch === undefined) continue;
          const list = pending.get(Number(entry.qstamp).toFixed(3) + ':' + v.pitch);
          if (!list || !list.length) continue;
          const n = list.shift();
          const el = document.getElementById(vid);
          if (el) {
            byId.set(n.id, el);
            toScale.set(vid, n.id);
            matched++;
          }
        }
      }
    }
    return { preserved, matched, total: notes.length };
  }

  async function load(url, notesUrl, z) {
    if (!tk) return;
    if (z) zoom = z;
    lastUrl = { url, notesUrl };
    status('Dibujando la partitura…');
    const t0 = performance.now();
    try {
      const [xml, notes] = await Promise.all([
        fetch(url, { cache: 'no-store' }).then((r) => r.text()),
        fetch(notesUrl, { cache: 'no-store' }).then((r) => r.json()),
      ]);
      const t1 = performance.now();
      tk.setOptions(options());
      if (!tk.loadData(xml)) throw new Error('Verovio no pudo leer la partitura');
      const pages = tk.getPageCount();
      const parts = [];
      for (let p = 1; p <= pages; p++) parts.push(tk.renderToSVG(p));
      const t2 = performance.now();
      scoreEl.innerHTML = parts.join('');
      lit = [];
      const index = buildIndex(notes);
      const t3 = performance.now();
      status('');
      send('loaded', {
        pages,
        fetchMs: Math.round(t1 - t0),
        engraveMs: Math.round(t2 - t1),
        domMs: Math.round(t3 - t2),
        svgKb: Math.round(parts.reduce((a, s) => a + s.length, 0) / 1024),
        preserved: index.preserved,
        matched: index.matched,
        total: index.total,
        width: document.documentElement.clientWidth,
        dpr: window.devicePixelRatio,
      });
    } catch (e) {
      status('No se pudo dibujar: ' + e.message);
      send('error', { message: String(e && e.message || e) });
    }
  }

  function systemOf(el) {
    return el.closest('g.system') || el.closest('g.measure') || el;
  }

  /** Resalta las notas [ids] y lleva el cursor a la primera. */
  function highlight(ids, follow) {
    for (const el of lit) el.classList.remove('hl');
    lit = [];
    for (const id of ids) {
      const el = byId.get(id);
      if (el) {
        el.classList.add('hl');
        lit.push(el);
      }
    }
    if (!lit.length) {
      cursorEl.style.display = 'none';
      return;
    }
    const noteRect = lit[0].getBoundingClientRect();
    const sysRect = systemOf(lit[0]).getBoundingClientRect();
    const top = sysRect.top + window.scrollY - 6;
    cursorEl.style.display = 'block';
    cursorEl.style.top = top + 'px';
    cursorEl.style.height = sysRect.height + 12 + 'px';
    cursorEl.style.left = noteRect.left + window.scrollX - 6 + 'px';
    cursorEl.style.right = 'auto';
    cursorEl.style.width = Math.max(18, noteRect.width + 12) + 'px';
    if (follow) {
      const vh = window.innerHeight;
      if (sysRect.top < vh * 0.08 || sysRect.bottom > vh * 0.92) {
        window.scrollTo({ top: Math.max(0, window.scrollY + sysRect.top - vh * 0.18), behavior: 'smooth' });
      }
    }
  }

  function clear() {
    highlight([], false);
  }

  /** Mide la fluidez: recorre la partitura con desplazamiento animado y
   * cuenta cuadros y cuadros lentos. */
  function bench(ms) {
    const total = ms || 4000;
    const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
    const start = performance.now();
    let last = start;
    let frames = 0;
    let slow = 0;
    let worst = 0;
    function step(now) {
      const dt = now - last;
      last = now;
      if (frames > 0) {
        if (dt > 25) slow++;
        worst = Math.max(worst, dt);
      }
      frames++;
      const t = Math.min(1, (now - start) / total);
      window.scrollTo(0, max * (t < 0.5 ? t * 2 : 2 - t * 2));
      if (t < 1) {
        requestAnimationFrame(step);
      } else {
        const secs = (now - start) / 1000;
        send('bench', { fps: Math.round(frames / secs), frames, slow, worstMs: Math.round(worst), scrollPx: max });
      }
    }
    requestAnimationFrame(step);
  }

  document.addEventListener('click', (ev) => {
    const el = ev.target.closest && ev.target.closest('g.note, g.chord, g.rest');
    if (!el) return;
    const note = el.classList.contains('chord') ? el.querySelector('g.note') : el;
    const id = note && (toScale.get(note.id) || note.id);
    if (id) send('tap', { id });
  });

  let resizeTimer = null;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      if (lastUrl) load(lastUrl.url, lastUrl.notesUrl);
    }, 300);
  });

  window.scale = { load, highlight, clear, bench, setZoom: (z) => { zoom = z; if (lastUrl) load(lastUrl.url, lastUrl.notesUrl); } };

  function start() {
    try {
      tk = new verovio.toolkit();
      status('');
      send('ready', { version: tk.getVersion() });
    } catch (e) {
      status('No se pudo iniciar el motor: ' + e.message);
      send('error', { message: String(e && e.message || e) });
    }
  }

  function whenBridge(fn) {
    if (window.ScaleBridge || (window.flutter_inappwebview && window.flutter_inappwebview.callHandler)) return fn();
    let tries = 0;
    const t = setInterval(() => {
      if (window.ScaleBridge || (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) || ++tries > 100) {
        clearInterval(t);
        fn();
      }
    }, 30);
  }

  if (typeof verovio === 'undefined') {
    status('No se encontró el motor de partituras');
    send('error', { message: 'verovio no está definido' });
  } else if (verovio.module.calledRun) {
    whenBridge(start);
  } else {
    verovio.module.onRuntimeInitialized = () => whenBridge(start);
  }
})();
