/* app.js — logica del frontend (bozza). Vedi DECISIONI-FRONTEND.md.
 *
 * Principio (decisione 7): la FOTO è l'hardware statico, il CODICE disegna sopra
 * il nome del modello e la ruota. Niente foto per-modello.
 */
(function () {
  'use strict';

  // --- Mappa numero-marce -> foto + ancora del pomello (decisioni 1, 7) ---
  // `knob` = centro del pomello in % dello stage, dove il codice scrive il nome.
  // Per le foto VERE: misurare l'ancora una volta e aggiornarla qui (TODO).
  const IMAGES = {
    6: { src: '../assets/shifter-6.svg', knob: { x: 50, y: 50 } },
    4: { src: '../assets/shifter-4.svg', knob: { x: 50, y: 48 } },
    0: { src: '../assets/knob-haiku.svg', knob: { x: 50, y: 40 } } // pomello giocattolo (decisione 6)
  };

  const el = {
    stage: document.getElementById('stage'),
    photo: document.getElementById('stagePhoto'),
    knobLabel: document.getElementById('knobLabel'),
    wheel: document.getElementById('modelWheel'),
    status: document.getElementById('shiftStatus'),
    ladderDots: document.getElementById('ladderDots'),
    ladderNote: document.getElementById('ladderNote'),
    ladder: document.getElementById('ladder'),
    ctxNum: document.getElementById('ctxNum'),
    planNum: document.getElementById('planNum'),
    modelNum: document.getElementById('modelNum')
  };

  let caps = null;        // ultimo snapshot capabilities
  let models = [];        // lista modelli (listModels)
  let busy = false;       // sto innestando? (decisione 3) — blocca altri comandi

  // ---- rendering ----

  function imageForGears(gears) {
    return IMAGES[gears] || IMAGES[6];
  }

  function render() {
    if (!caps) return;
    const img = imageForGears(caps.gears);

    // strato foto
    if (!el.photo.src.endsWith(img.src.split('/').pop())) el.photo.src = img.src;

    // nome del modello SOPRA il pomello, all'ancora della foto (decisione 4)
    el.knobLabel.textContent = caps.model;
    el.knobLabel.style.left = img.knob.x + '%';
    el.knobLabel.style.top = img.knob.y + '%';
    el.knobLabel.hidden = false;

    renderLadder();

    // cruscotto
    el.ctxNum.textContent = caps.usage.contextPct + '%';
    el.planNum.textContent = caps.usage.planPct + '%';
    el.modelNum.textContent = caps.model;
  }

  // ladder effort disegnato DA capabilities, non hardcoded (decisione 2)
  function renderLadder() {
    el.ladderDots.innerHTML = '';
    if (!caps.effort.hasControl) {
      el.ladder.classList.add('disabled');
      el.ladderNote.textContent = caps.model + ' non ha lo splitter — nessun effort.';
      return;
    }
    el.ladder.classList.remove('disabled');
    caps.gearLabels.forEach((label, i) => {
      const dot = document.createElement('div');
      dot.className = 'dot' + (i === caps.effort.level ? ' active' : '');
      dot.textContent = label;
      dot.title = 'Marcia ' + (i + 1) + ' di ' + caps.gears;
      dot.addEventListener('click', () => shiftEffort(i));
      el.ladderDots.appendChild(dot);
    });
    el.ladderNote.textContent =
      caps.gears + ' marce · innestata: ' + caps.effort.label;
  }

  // ---- ruota dei modelli (decisioni 4-5) ----

  function openWheel() {
    if (busy) return;
    el.wheel.innerHTML = '';
    const ring = document.createElement('div');
    ring.className = 'wheel-ring';

    const n = models.length;
    const radius = 44; // % del raggio dell'anello
    models.forEach((name, i) => {
      // parti dall'alto (-90°) e distribuisci in cerchio
      const angle = (-90 + (360 / n) * i) * (Math.PI / 180);
      const x = 50 + radius * Math.cos(angle);
      const y = 50 + radius * Math.sin(angle);
      const item = document.createElement('button');
      item.className = 'wheel-item' + (name === caps.model ? ' current' : '');
      item.style.left = x + '%';
      item.style.top = y + '%';
      item.textContent = name;
      item.addEventListener('click', () => {
        closeWheel();
        if (name !== caps.model) shiftModel(name);
      });
      ring.appendChild(item);
    });

    const center = document.createElement('div');
    center.className = 'wheel-center';
    center.textContent = 'scegli il modello';
    ring.appendChild(center);

    el.wheel.appendChild(ring);
    el.wheel.hidden = false;
  }

  function closeWheel() { el.wheel.hidden = true; }

  // ---- azioni: cambio marcia con stato onesto + retry (decisioni 3, 8) ----

  function setStatus(text, retry) {
    if (!text) { el.status.hidden = true; el.status.innerHTML = ''; return; }
    el.status.hidden = false;
    el.status.className = 'shift-status' + (retry ? ' retry' : '');
    el.status.innerHTML = '<span class="spinner"></span>' + text;
  }

  async function shiftModel(name) {
    if (busy) return;
    busy = true;
    try {
      setStatus('Innesto ' + name + '…', false);
      let res = await window.Broker.setModel(name);

      // setModel fallito NON prova che il modello non esista (decisione 8):
      // il backend ritenta da solo, la GUI mostra "riprovo" e ritenta una volta.
      if (!res.ok) {
        setStatus('Submenu bloccato, riprovo ' + name + '…', true);
        res = await window.Broker.setModel(name);
      }
      if (!res.ok) {
        setStatus('Non riuscito: ' + name + ' (' + res.error + ')', true);
        await sleep(1600);
        setStatus(null);
        return;
      }

      // dopo un cambio modello la griglia va RIletta (decisione 2): capabilities.
      setStatus('Leggo la griglia…', false);
      caps = await window.Broker.capabilities();
      render();
    } finally {
      setStatus(null);
      busy = false;
    }
  }

  async function shiftEffort(level) {
    if (busy || !caps.effort.hasControl || level === caps.effort.level) return;
    busy = true;
    try {
      setStatus('Innesto marcia ' + (level + 1) + '…', false);
      const res = await window.Broker.setEffort(level);
      if (res.ok) {
        // read-back onesto: rileggo lo stato invece di fidarmi dell'intenzione
        caps = await window.Broker.capabilities();
        render();
      }
    } finally {
      setStatus(null);
      busy = false;
    }
  }

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // ---- eventi ----

  // clic destro sul pomello → apre la ruota (menu contestuale soppresso)
  el.stage.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    if (el.wheel.hidden) openWheel(); else closeWheel();
  });
  // clic fuori dalla ruota la chiude
  el.wheel.addEventListener('click', (e) => { if (e.target === el.wheel) closeWheel(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeWheel(); });

  // ---- avvio ----
  (async function init() {
    setStatus('Aggancio…', false);
    models = await window.Broker.listModels();
    caps = await window.Broker.capabilities();
    setStatus(null);
    render();
  })();
})();
