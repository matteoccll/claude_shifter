#!/usr/bin/env node
'use strict';
// Diagnostic: open a popup, record its whole contents, close it.
// Does not move the slider or change the model, so nothing changes.
// Output goes to popup-report.txt.
//
//   node backend/effortpopup.js          the effort popup
//   node backend/effortpopup.js model    the model menu, submenu included

const path = require('path');
const { Broker, withDeadline, makeReport } = require('./client');

const REPORT = makeReport(path.join(__dirname, 'popup-report.txt'));
const say = (...a) => REPORT.log(...a);

(async () => {
  withDeadline(240, REPORT, 'ispezione menu');
  const target = process.argv[2] === 'model' ? 'model' : 'effort';
  const b = new Broker({ onLog: l => say(l) });
  await b.start();

  const gear = await b.send('readGear');
  say(`Modello attivo: ${gear.model}`);
  say(`Effort attivo : ${gear.hasEffort ? gear.effort : '(assente)'}`);
  say('');

  if (target === 'model') {
    const m = await b.send('modelPopupTree');
    say(`Sottomenu aperti: ${m.submenusOpened}`);
    say(`--- contenuto del menu modelli (${m.count} elementi) ---`);
    say(m.text || '(vuoto)');

    const { models } = await b.send('listModels');
    say('');
    say(`--- modelli riconosciuti (${models.length}) ---`);
    models.forEach(x => say(`  ${x.label}   (grezzo: "${x.name}")${x.enabled ? '' : '  [disabilitato]'}${x.selected ? '  <- attivo' : ''}`));
  } else {
    const r = await b.send('effortPopupTree');
    say(`Cursore: ${r.slider}`);
    say(`--- contenuto del menu effort (${r.count} elementi) ---`);
    say(r.text || '(vuoto)');
  }

  b.stop();
  REPORT.flush();
})().catch(err => {
  say('');
  say(`ERRORE: ${err.message}`);
  REPORT.flush();
  process.exit(1);
});
