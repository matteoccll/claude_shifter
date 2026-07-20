#!/usr/bin/env node
'use strict';
// Diagnostic: print every named UI element Claude Desktop exposes, grouped by
// control type. Read-only.
//
//   node backend/dump.js            all elements
//   node backend/dump.js Button     only that control type

const { Broker, withDeadline } = require('./client');

(async () => {
  withDeadline(240, null, 'dump');
  const filter = process.argv[2];
  const b = new Broker({ verbose: false });
  await b.start();

  const { count, text } = await b.send('dump');
  const rows = (text || '').split('\n').filter(Boolean).map(l => {
    const [ct, ...rest] = l.split('\t');
    return { ct, name: rest.join('\t') };
  });

  const groups = new Map();
  for (const r of rows) {
    if (filter && r.ct !== filter) continue;
    if (!groups.has(r.ct)) groups.set(r.ct, []);
    groups.get(r.ct).push(r.name);
  }

  console.log(`${count} elementi con nome\n`);
  for (const [ct, names] of [...groups].sort((a, b) => b[1].length - a[1].length)) {
    console.log(`=== ${ct} (${names.length}) ===`);
    names.forEach(n => console.log(`  ${n}`));
    console.log();
  }

  b.stop();
})().catch(err => {
  console.error('ERRORE:', err.message);
  process.exit(1);
});
