#!/usr/bin/env node
'use strict';
// Quick read-only state check: what model / effort is the app on right now?
//
//   node backend/state.js

const { Broker, withDeadline } = require('./client');

(async () => {
  withDeadline(120, 'lettura stato');
  const t0 = Date.now();
  const b = new Broker({ verbose: false });
  await b.start();
  console.log(`(agganciato in ${((Date.now() - t0) / 1000).toFixed(1)}s)`);
  const g = await b.send('readGear');
  console.log(`modello : ${g.model}`);
  console.log(`effort  : ${g.hasEffort ? g.effort : '(assente)'}`);
  if (g.hasEffort) {
    const r = await b.send('effortRange');
    if (r.available) console.log(`cursore : ${r.current} (scala ${r.min}-${r.max})`);
  }
  b.stop();
})().catch(err => { console.error('ERRORE:', err.message); process.exit(1); });
