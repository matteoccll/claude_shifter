/* mockBroker.js — finto backend, così il frontend gira da solo.
 *
 * Espone gli STESSI comandi del broker UIA vero (vedi SPEC §4.1):
 *   listModels()        -> [nomi]
 *   capabilities()      -> snapshot completo per la GUI
 *   setModel(nome)      -> {ok} | {ok:false, error}
 *   setEffort(livello)  -> {ok}
 *   readUsage()         -> {contextPct, planPct}
 *
 * Le latenze sono quelle MISURATE dal vivo (sessioni 14-16):
 *   setModel ~1,6 s · capabilities ~2,2 s · picco raro ~4 s.
 * Sostituendo questo file col broker vero, la app non cambia: stessi nomi,
 * stesse forme di risposta. Vedi DECISIONI-FRONTEND.md (TODO).
 */
(function () {
  'use strict';

  // Ladder marce per modello (PROJECT §3.1, letta dal vivo → gearbox.json).
  // Le etichette seguono le FOTO (inglese sul gate); il backend vero le legge
  // localizzate — la GUI mostra comunque la read-back dell'etichetta.
  const GEARS_6 = ['Low', 'Medium', 'High', 'Extra', 'Max', 'Ultracode'];
  const GEARS_4 = ['Low', 'Medium', 'High', 'Max']; // salta Extra e Ultracode

  const MODELS = {
    'Fable 5':    { gears: GEARS_6 },
    'Opus 4.8':   { gears: GEARS_6 },
    'Opus 4.7':   { gears: GEARS_6 },
    'Sonnet 5':   { gears: GEARS_6 },
    'Opus 4.6':   { gears: GEARS_4 },
    'Sonnet 4.6': { gears: GEARS_4 },
    'Haiku 4.5':  { gears: [] }     // nessuno splitter
  };
  const ORDER = ['Fable 5', 'Opus 4.8', 'Opus 4.7', 'Sonnet 5', 'Opus 4.6', 'Sonnet 4.6', 'Haiku 4.5'];

  // Stato interno finto (l'app vera lo legge dall'app Claude, non lo tiene).
  let current = 'Opus 4.8';
  let effortLevel = 2; // indice nella ladder
  let contextPct = 10;
  let planPct = 41;

  const delay = (ms) => new Promise((r) => setTimeout(r, ms));
  // jitter attorno a un valore, con un picco raro (come il ~4 s residuo).
  function timing(base, spread, spikeChance, spike) {
    if (Math.random() < spikeChance) return spike + Math.random() * 400;
    return base + (Math.random() - 0.5) * spread;
  }

  function snapshot() {
    const m = MODELS[current];
    const gears = m.gears;
    const hasControl = gears.length > 0;
    if (effortLevel > gears.length - 1) effortLevel = Math.max(0, gears.length - 1);
    return {
      model: current,
      models: ORDER.slice(),
      gears: gears.length,
      gearLabels: gears.slice(),
      effort: {
        level: hasControl ? effortLevel : null,
        label: hasControl ? gears[effortLevel] : null,
        hasControl,
        range: hasControl ? [0, gears.length - 1] : null
      },
      usage: { contextPct, planPct },
      errors: []
    };
  }

  const Broker = {
    async listModels() {
      await delay(timing(700, 300, 0, 0));
      return ORDER.slice();
    },

    async capabilities() {
      // ~2,2 s in condizioni buone, picco raro ~4 s (sessione 16).
      await delay(timing(2200, 600, 0.12, 4000));
      return snapshot();
    },

    async setModel(name) {
      // ~1,6 s (sessione 14).
      await delay(timing(1600, 500, 0, 0));
      if (!MODELS[name]) return { ok: false, error: 'Model option not found' };
      // Bug del sottomenu §10: ~1 volta su 7 i modelli "nascosti" falliscono.
      const hidden = ['Opus 4.7', 'Opus 4.6', 'Sonnet 4.6'];
      if (hidden.includes(name) && Math.random() < 0.35) {
        return { ok: false, error: 'Model option not found (submenu 4 -> 0)' };
      }
      current = name;
      // un cambio modello muove un po' i consumi, giusto per far vivere il cruscotto
      contextPct = Math.min(99, contextPct + Math.floor(Math.random() * 6));
      return { ok: true, model: current };
    },

    async setEffort(level) {
      await delay(timing(1300, 400, 0, 0));
      const m = MODELS[current];
      if (m.gears.length === 0) return { ok: false, error: 'No effort control on this model' };
      effortLevel = Math.max(0, Math.min(m.gears.length - 1, level));
      return { ok: true, level: effortLevel, label: m.gears[effortLevel] };
    },

    async readUsage() {
      await delay(200);
      return { contextPct, planPct };
    }
  };

  window.Broker = Broker;
})();
