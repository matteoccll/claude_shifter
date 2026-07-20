#!/usr/bin/env node
'use strict';
// Diagnostic: dump the UI tree to a file, and print the branch around a match.
//
//   node backend/tree.js                    write full tree to tree.txt
//   node backend/tree.js "Backend setup"    also print that node's ancestors
//                                           and siblings

const fs = require('fs');
const path = require('path');
const { Broker } = require('./client');

const OUT = path.join(__dirname, 'tree.txt');

(async () => {
  const needle = process.argv[2];
  const b = new Broker({ verbose: false });
  await b.start();

  const { count, text } = await b.send('dumpTree');
  fs.writeFileSync(OUT, text, 'utf8');
  console.log(`${count} nodi scritti in ${OUT}\n`);

  if (needle) {
    const lines = text.split('\n');
    const depthOf = l => (l.match(/^ */)[0].length) / 2;
    const idx = lines.findIndex(l => l.split('\t')[0].trim() === needle
                                  || l.split('\t')[1] === needle);
    if (idx < 0) { console.log(`"${needle}" non trovato`); b.stop(); return; }

    console.log(`--- catena di antenati di "${needle}" ---`);
    let d = depthOf(lines[idx]);
    const chain = [lines[idx]];
    for (let i = idx - 1; i >= 0 && d > 0; i--) {
      if (depthOf(lines[i]) < d) { chain.unshift(lines[i]); d = depthOf(lines[i]); }
    }
    chain.forEach(l => console.log(l));

    console.log(`\n--- fratelli (stesso livello, stesso genitore) ---`);
    const myDepth = depthOf(lines[idx]);
    let start = idx;
    while (start > 0 && depthOf(lines[start - 1]) >= myDepth) start--;
    let end = idx;
    while (end + 1 < lines.length && depthOf(lines[end + 1]) >= myDepth) end++;
    for (let i = start; i <= end; i++) {
      if (depthOf(lines[i]) === myDepth) console.log(lines[i]);
    }
  }

  b.stop();
})().catch(err => {
  console.error('ERRORE:', err.message);
  process.exit(1);
});
