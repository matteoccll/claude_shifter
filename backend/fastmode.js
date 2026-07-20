#!/usr/bin/env node
'use strict';
// Read, or put back, the model menu's "fast mode" switch.
//
//   node backend/fastmode.js         read only
//   node backend/fastmode.js off     turn it off
//   node backend/fastmode.js on      turn it on

const path = require('path');
const { Broker, withDeadline, makeReport } = require('./client');

const REPORT = makeReport(path.join(__dirname, 'fastmode-report.txt'));
const say = (...a) => REPORT.log(...a);

(async () => {
  withDeadline(180, REPORT, 'modalita veloce');
  const arg = process.argv[2];
  const set = arg === 'on' ? true : arg === 'off' ? false : undefined;

  const b = new Broker({ onLog: l => say(l) });
  await b.start();

  const args = set === undefined ? {} : { set };
  const r = await b.send('fastMode', args);

  say(`titolo menu   : ${r.menuTitle}`);
  say(`voce switch   : ${r.toggleName ?? '(non trovata)'}`);
  say(`stato switch  : ${r.toggleState ?? '(illeggibile)'}`);
  if (r.changed) {
    say(`--- modificato ---`);
    say(`titolo dopo   : ${r.menuTitleAfter}`);
    say(`stato dopo    : ${r.toggleStateAfter ?? '(illeggibile)'}`);
  } else if (set !== undefined) {
    say(`(nessuna modifica necessaria)`);
  }

  b.stop();
  REPORT.flush();
})().catch(err => {
  say(`ERRORE: ${err.message}`);
  REPORT.flush();
  process.exit(1);
});
