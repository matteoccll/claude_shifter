#!/usr/bin/env node
'use strict';
// Collaudo MANUALE del ramo "app davvero chiusa". Va guidato a mano e va
// lanciato DA UN TERMINALE ESTERNO, non da dentro Claude: chiudere l'app chiude
// anche chi la sta pilotando, se sono la stessa app.
//
// Differenza da reattach.js: quello simula la perdita con `forceDetach` senza
// toccare l'app, e prova solo la meta' cara del recupero. Questo chiude l'app
// per davvero, quindi prova anche il rilevamento della morte del processo --
// l'unico pezzo che il collaudo automatico non puo' raggiungere.
//
// Perche' si parte con l'app APERTA: all'avvio il broker, se non trova Claude,
// la lancia lui. Partire a app chiusa se la riaprirebbe da solo e il collaudo
// non proverebbe nulla.
//
// Atteso:
//   1. app aperta      -> letture ok
//   2. app chiusa      -> evento `detached` + errore
//                         "Claude Desktop is not running - reopen it and retry"
//                         (un errore chiaro, NON un crash e NON l'app che si
//                         riapre da sola)
//   3. app riaperta    -> evento `reattached` con pid NUOVO, letture di nuovo ok,
//                         senza aver riavviato il broker
//
// NON CAMBIA NULLA: solo letture.
// Output a schermo e in detachtest-report.txt.
//
//   node backend/detachtest.js [giri]        (default 36 giri x 5s = 3 minuti)

const path = require('path');
const { Broker, withDeadline, makeReport } = require('./client');

const ROUNDS = Number(process.argv[2] || 36);
const REPORT = makeReport(path.join(__dirname, 'detachtest-report.txt'));
const sleep  = ms => new Promise(r => setTimeout(r, ms));

// A schermo e su file: lo guardi mentre gira, e resta scritto per dopo.
const say = (...a) => { console.log(a.join(' ')); REPORT.log(a.join(' ')); };

(async () => {
  withDeadline(ROUNDS * 5 + 180, REPORT, 'collaudo app chiusa');

  const events = [];
  const b = new Broker({
    onLog: l => REPORT.log(l),   // il rumore del broker solo su file
    onEvent: e => { events.push(e); say(`   >>> EVENTO ${e.event} ${JSON.stringify(e)}`); },
  });

  const { pid } = await b.start();
  say(`Agganciato a Claude pid=${pid}`);
  say('');
  say('==================================================================');
  say(' ORA, mentre questo gira:');
  say('   1. CHIUDI Claude Desktop (chiusura vera, anche dalla barra');
  say('      delle applicazioni se resta li\')');
  say('   2. aspetta 3-4 giri e guarda gli errori');
  say('   3. RIAPRI Claude Desktop e aspetta che carichi');
  say('==================================================================');
  say('');

  let sawDetached = false, sawReattached = false, okAfter = false, firstPid = pid;

  for (let i = 1; i <= ROUNDS; i++) {
    try {
      const g = await b.send('readGear');
      say(`${String(i).padStart(2)}. ok  -> ${g.model} / ${g.hasEffort ? g.effort : '(no effort)'}`);
      if (sawDetached) okAfter = true;
    } catch (e) {
      say(`${String(i).padStart(2)}. ERR -> ${e.message}`);
    }
    if (events.some(e => e.event === 'detached'))   sawDetached = true;
    if (events.some(e => e.event === 'reattached')) sawReattached = true;
    const rp = events.filter(e => e.event === 'reattached').pop();
    if (rp) firstPid = rp.pid;
    events.length = 0;
    await sleep(5000);
  }

  b.stop();
  say('');
  say('--- esito ---');
  say(`app rilevata come chiusa (evento detached): ${sawDetached ? 'SI' : 'NO'}`);
  say(`riagganciata da sola (evento reattached)  : ${sawReattached ? 'SI' : 'NO'}`);
  say(`letture tornate a funzionare              : ${okAfter ? 'SI' : 'NO'}`);
  if (sawReattached) say(`pid dopo il riaggancio                    : ${firstPid}`);
  say('');
  if (sawDetached && sawReattached && okAfter) say('ESITO: il ramo "app chiusa" funziona come previsto.');
  else if (!sawDetached) say('ESITO: l\'app non e\' mai risultata chiusa. Era chiusa davvero? (processo residuo?)');
  else say('ESITO: persa e non recuperata. Guarda le righe qui sopra.');
  REPORT.flush();
})().catch(err => {
  say('');
  say(`ERRORE: ${err.message}`);
  REPORT.flush();
  process.exit(1);
});
