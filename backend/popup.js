#!/usr/bin/env node
'use strict';
// Diagnostic: open a popup and report what it contains, then close it.
// Changes nothing -- the popup is dismissed with Escape.
//
//   node backend/popup.js effort
//   node backend/popup.js model

const { Broker } = require('./client');

(async () => {
  const target = process.argv[2] || 'effort';
  const b = new Broker({ verbose: true });
  await b.start();

  const gear = await b.send('readGear');
  console.log(`\nModello attivo: ${gear.model}`);
  console.log(`Effort attivo : ${gear.hasEffort ? gear.effort : '(assente)'}\n`);

  const { count, text } = await b.send('dumpOpen', { target });
  console.log(`--- comparso aprendo il menu "${target}" (${count} elementi) ---`);
  console.log(text || '(niente)');

  b.stop();
})().catch(err => {
  console.error('ERRORE:', err.message);
  process.exit(1);
});
