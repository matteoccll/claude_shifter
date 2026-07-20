#!/usr/bin/env node
'use strict';
// Collaudo del riaggancio automatico.
//
// Perche' non chiude l'app per davvero: il broker si aggancia al processo
// "Claude", che e' la stessa app dentro cui gira chi lo sta pilotando. Chiuderla
// per provare il recupero significa chiudere anche il collaudo. Quindi si usa
// `forceDetach`, che butta via l'aggancio senza toccare l'app: il comando
// successivo deve ritrovare la finestra da solo.
//
// Cosa NON copre: il caso in cui l'app e' davvero morta. Quel ramo va provato a
// mano una volta, da un terminale esterno, con l'app Claude chiusa (atteso:
// evento `detached` ed errore chiaro, non un crash).
//
// NON CAMBIA NULLA: solo letture.
// Output in reattach-report.txt, non a console.
//
//   node backend/reattach.js [giri]

const path = require('path');
const { Broker, withDeadline, makeReport } = require('./client');

const ROUNDS = Number(process.argv[2] || 3);
const REPORT = makeReport(path.join(__dirname, 'reattach-report.txt'));
const say    = (...a) => REPORT.log(...a);

(async () => {
  withDeadline(300, REPORT, 'collaudo riaggancio');

  const events = [];
  const b = new Broker({
    onLog: l => say(l),
    onEvent: e => { events.push(e); say(`  >>> EVENTO ${e.event}: ${JSON.stringify(e)}`); },
  });

  const { pid } = await b.start();
  say(`Agganciato a Claude pid=${pid}`);

  let ok = 0;
  for (let i = 1; i <= ROUNDS; i++) {
    say('');
    say(`--- giro ${i} ---`);

    const before = await b.send('readGear');
    say(`lettura prima  : ${before.model} / ${before.hasEffort ? before.effort : '(no effort)'}`);

    await b.send('forceDetach');
    say('aggancio buttato via');

    const t0 = Date.now();
    const after = await b.send('readGear');
    const ms = Date.now() - t0;
    say(`lettura dopo   : ${after.model} / ${after.hasEffort ? after.effort : '(no effort)'}  (${ms} ms)`);

    const sameRead = after.model === before.model;
    const gotEvent = events.some(e => e.event === 'reattached');
    if (sameRead && gotEvent) { ok++; say('esito giro     : riagganciato da solo'); }
    else say(`esito giro     : PROBLEMA (lettura coerente=${sameRead}, evento reattached=${gotEvent})`);
    events.length = 0;
  }

  b.stop();
  say('');
  say(ok === ROUNDS
    ? `ESITO: ${ok}/${ROUNDS} recuperi riusciti. Il riaggancio funziona.`
    : `ESITO: solo ${ok}/${ROUNDS} recuperi riusciti. Da guardare.`);
  REPORT.flush();
})().catch(err => {
  say('');
  say(`ERRORE: ${err.message}`);
  REPORT.flush();
  process.exit(1);
});
