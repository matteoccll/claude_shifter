#!/usr/bin/env node
'use strict';
// Ask the broker the one question the GUI is meant to ask, and print the answer
// the way the lever would read it.
//
// NON CAMBIA NULLA: apre e richiude il menu modello e il popup dell'effort per
// leggerli, ma non innesta niente. Lo stato dell'app resta com'era.
//
// Output in capabilities-report.txt, non a console.
//
//   node backend/capabilities.js

const path = require('path');
const { Broker, withDeadline, makeReport } = require('./client');

const REPORT = makeReport(path.join(__dirname, 'capabilities-report.txt'));
const say    = (...a) => REPORT.log(...a);

// Il contatore Usage dell'app ha due formati (percentuale o token assoluti):
// il broker riporta il campo che c'era, qui si mostra quello.
function fmtUsage(u) {
  if (!u) return '(non leggibile)';
  const ctx = u.contextPct != null ? `contesto ${u.contextPct}%`
            : u.contextTokens != null ? `contesto ${(u.contextTokens / 1000).toFixed(1)}k token`
            : `contesto ? (grezzo: "${u.raw}")`;
  const plan = u.planPct != null ? `piano ${u.planPct}%` : 'piano ?';
  return `${ctx}, ${plan}`;
}

(async () => {
  withDeadline(180, REPORT, 'capabilities');
  const b = new Broker({ onLog: l => say(l), onEvent: e => say(`[evento] ${JSON.stringify(e)}`) });
  await b.start();

  const t0 = Date.now();
  const c = await b.capabilities();
  const ms = Date.now() - t0;
  b.stop();

  say('');
  say(`--- capabilities (${ms} ms) ---`);
  say(`Marcia innestata : ${c.model}`);
  say(`Effort           : ${c.hasEffort ? c.effort : '(questo modello non ha lo splitter)'}`);
  say(`Marce disponibili: ${c.gears}${c.effortRange.available ? ` (cursore ${c.effortRange.min}-${c.effortRange.max}, ora ${c.effortRange.current})` : ` -- ${c.effortRange.reason}`}`);
  say(`Cruscotto        : ${fmtUsage(c.usage)}`);
  say('');
  say(`Modelli offerti dall'app (${c.models.length}):`);
  c.models.forEach(m => say(
    `  ${m.label}${m.enabled ? '' : '  [disabilitato]'}${m.selected ? '  <- attivo' : ''}`
  ));

  if (c.errors.length) {
    say('');
    say('Sezioni non lette (la risposta e\' comunque valida per il resto):');
    c.errors.forEach(e => say(`  ! ${e}`));
  }

  say('');
  say('Questo e\' tutto cio\' che serve alla GUI per disegnare la leva.');
  say('Va richiesto di nuovo dopo ogni setModel: la griglia cambia con il modello.');
  REPORT.flush();
})().catch(err => {
  say('');
  say(`ERRORE: ${err.message}`);
  REPORT.flush();
  process.exit(1);
});
