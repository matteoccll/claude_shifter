#!/usr/bin/env node
'use strict';
// Read-only check: does the broker attach and read the app correctly?
// Changes nothing. Opening the model menu is the only side effect, and it is
// closed again with ExpandCollapse.Collapse (never with synthetic keys).
//
//   node backend/probe.js

const { Broker, withDeadline } = require('./client');

(async () => {
  withDeadline(300, null, 'probe');
  const b = new Broker({ verbose: true });

  console.log('Avvio broker...\n');
  const { pid } = await b.start();
  console.log(`Agganciato a Claude Desktop (pid ${pid})\n`);

  const gear = await b.send('readGear');
  console.log('Marcia corrente:');
  console.log(`  modello : ${gear.model}`);
  console.log(`  effort  : ${gear.hasEffort ? gear.effort : '(questo modello non ha effort)'}\n`);

  try {
    const u = await b.send('readUsage');
    const ctx = u.contextPct != null ? `${u.contextPct}%`
              : u.contextTokens != null ? `${(u.contextTokens / 1000).toFixed(1)}k token`
              : `? (grezzo: "${u.raw}")`;
    console.log(`Cruscotto: contesto ${ctx}  ·  piano ${u.planPct != null ? u.planPct + '%' : '?'}\n`);
  } catch (e) {
    console.log(`Cruscotto: non leggibile (${e.message})\n`);
  }

  const enu = await b.send('enumerate');
  console.log(`Conversazioni trovate: ${enu.count}`);
  (enu.text || '').split('\n').filter(Boolean).forEach(l => {
    const [title, status] = l.split('\t');
    console.log(`  ${title}${status ? `   [${status}]` : ''}`);
  });
  console.log();

  const { models } = await b.send('listModels');
  console.log(`Modelli nel menu: ${models.length}`);
  for (const m of models) {
    const flags = [
      m.selected ? 'ATTIVO' : null,
      m.enabled ? null : 'disabilitato',
    ].filter(Boolean).join(', ');
    console.log(`  ${m.name}${flags ? '   [' + flags + ']' : ''}`);
  }

  console.log('\nLettura completata — nulla è stato modificato.');
  b.stop();
})().catch(err => {
  console.error('\nERRORE:', err.message);
  process.exit(1);
});
