#!/usr/bin/env node
'use strict';
// Map the gearbox: for every model the app offers, how many effort detents it
// has and what each one is called.
//
// THIS CHANGES THINGS. It switches model and sweeps the effort slider on the
// conversation currently open in Claude Desktop, then puts both back. The
// original model and effort are captured first and restored in a finally block
// so an error partway through still leaves the app as it was found.
//
// Output goes to map-report.txt and gearbox.json, not to the console.
//
//   node backend/map.js

const fs = require('fs');
const path = require('path');
const { Broker, withDeadline, makeReport } = require('./client');

const JSON_OUT = path.join(__dirname, 'gearbox.json');
const REPORT   = makeReport(path.join(__dirname, 'map-report.txt'));
const say      = (...a) => REPORT.log(...a);

(async () => {
  withDeadline(900, REPORT, 'mappatura');
  const b = new Broker({ onLog: l => say(l) });
  await b.start();

  const start = await b.send('readGear');
  say(`Stato iniziale: modello=${start.model} effort=${start.hasEffort ? start.effort : '(assente)'}`);

  const startRange = start.hasEffort ? await b.send('effortRange') : { available: false };
  const startLevel = startRange.available ? startRange.current : null;
  say(`Cursore iniziale: ${startLevel === null ? '(nessuno)' : startLevel}`);
  say('');

  const { models } = await b.send('listModels');
  say(`Modelli offerti dall'app (${models.length}):`);
  models.forEach(m => say(`  ${m.label}${m.enabled ? '' : '  [disabilitato]'}${m.selected ? '  <- attivo' : ''}`));
  say('');

  const result = { probedAt: new Date().toISOString(), models: [] };

  try {
    for (const m of models) {
      if (!m.enabled) {
        say(`--- ${m.label}: disabilitato, salto ---`);
        result.models.push({ model: m.label, enabled: false });
        continue;
      }

      say(`--- ${m.label} ---`);
      let applied;
      try {
        applied = (await b.send('setModel', { model: m.label })).model;
      } catch (e) {
        say(`  cambio modello FALLITO: ${e.message}`);
        result.models.push({ model: m.label, enabled: true, error: e.message });
        continue;
      }
      say(`  modello attivo: ${applied}`);

      const probe = await b.send('probeEffort');
      if (!probe.available) {
        say(`  effort: NESSUNO (${probe.reason})`);
        result.models.push({ model: applied, enabled: true, effort: null, reason: probe.reason });
        continue;
      }

      const levels = (probe.positions || '').split('\n').filter(Boolean).map(l => {
        const [value, label] = l.split('\t');
        return { value: Number(value), label: label || null };
      });
      const usable = levels.filter(l => l.label);
      say(`  effort: cursore ${probe.min}-${probe.max}, ${usable.length} livelli distinti leggibili`);
      levels.forEach(l => say(`    ${l.value} = ${l.label ?? '(illeggibile)'}`));
      if (!probe.restoredOk) say('  ATTENZIONE: ripristino cursore incerto');

      result.models.push({ model: applied, enabled: true, min: probe.min, max: probe.max, levels });
    }
  } finally {
    say('');
    say('--- ripristino stato iniziale ---');
    try {
      const back = await b.send('setModel', { model: start.model });
      say(`  modello: ${back.model}`);
      if (startLevel !== null) {
        const e = await b.send('setEffort', { level: startLevel });
        say(`  effort : ${e.effort}`);
      }
      const now = await b.send('readGear');
      const ok = now.model === start.model
              && (!start.hasEffort || now.effort === start.effort);
      say(`  verifica: modello=${now.model} effort=${now.hasEffort ? now.effort : '(assente)'}`);
      say(`  ${ok ? 'RIPRISTINATO come era' : 'DIVERSO DA COME ERA - controlla a mano'}`);
    } catch (e) {
      say(`  RIPRISTINO FALLITO: ${e.message}`);
      say(`  rimetti a mano: modello ${start.model}, effort ${start.effort}`);
    }
    b.stop();
  }

  fs.writeFileSync(JSON_OUT, JSON.stringify(result, null, 2), 'utf8');
  say('');
  say(`Mappa salvata in ${JSON_OUT}`);
  REPORT.flush();
})().catch(err => {
  say('');
  say(`ERRORE: ${err.message}`);
  REPORT.flush();
  process.exit(1);
});
