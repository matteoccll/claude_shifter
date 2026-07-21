#!/usr/bin/env node
'use strict';
// Collaudo M1: enumerate -> selectSession -> setModel -> setEffort, con
// verifica rileggendo le etichette a ogni passo e ripristino totale dello
// stato di partenza (vincolo: ogni test che cambia marcia la rimette a posto).
//
// CAMBIA E RIPRISTINA: modello ed effort della conversazione attiva vengono
// spostati e riportati indietro; la verifica finale rilegge lo stato e
// confronta con la partenza.
//
// Il giro di selectSession (andata su un'altra sessione e ritorno) si fa solo
// se gli passi il titolo della conversazione ATTIVA: lo script non ha modo di
// capire da solo quale sia, e senza saperlo non saprebbe dove tornare.
//
//   node backend/test.js                       salta il giro di selectSession
//   node backend/test.js "<titolo attivo>"     giro completo
//
// Output in test-report.txt, non a console.

const path = require('path');
const { Broker, withDeadline, makeReport } = require('./client');

const HOME   = process.argv[2] || null;
const REPORT = makeReport(path.join(__dirname, 'test-report.txt'));
const say    = (...a) => REPORT.log(...a);

let failures = 0;
let effortTested = false;   // false finche' setEffort non e' stato davvero esercitato
const check = (label, ok, detail) => {
  say(`${ok ? 'OK ' : 'FAIL'}  ${label}${detail ? `  (${detail})` : ''}`);
  if (!ok) failures++;
};

(async () => {
  withDeadline(420, REPORT, 'collaudo M1');
  const b = new Broker({ onLog: l => say(l), onEvent: e => say(`  >>> evento ${e.event}`) });
  const { pid } = await b.start();
  say(`Agganciato a Claude pid=${pid}`);
  say('');

  // 1. enumerate
  const enu = await b.send('enumerate');
  const rows = (enu.text || '').split('\n').filter(Boolean).map(l => {
    const [title, status] = l.split('\t');
    return { title, status: status || '' };
  });
  say(`[1] sessioni (${rows.length}): ${rows.map(r => `"${r.title}"${r.status ? ` [${r.status}]` : ''}`).join(', ')}`);
  check('enumerate trova sessioni', rows.length > 0);

  // 2. stato di partenza
  const start = await b.send('readGear');
  say(`[2] partenza: ${start.model} / ${start.hasEffort ? start.effort : '(no effort)'}`);

  const startRange = start.hasEffort ? await b.send('effortRange') : { available: false, hasControl: false };
  const startLevel = startRange.available ? startRange.current : null;
  say(`    cursore: ${startLevel === null ? '(nessuno)' : `${startLevel} (scala ${startRange.min}-${startRange.max})`}`);

  try {
    // 3. selectSession andata e ritorno (solo con HOME noto, vedi intestazione)
    const other = HOME ? rows.find(r => r.title !== HOME) : null;
    if (HOME && !rows.some(r => r.title === HOME)) {
      check(`la sessione attiva dichiarata ("${HOME}") esiste in sidebar`, false);
    } else if (HOME && other) {
      say('');
      say(`[3] selectSession -> "${other.title}"`);
      await b.send('selectSession', { name: other.title });
      const gOther = await b.send('readGear');
      say(`    marcia dell'altra sessione: ${gOther.model} / ${gOther.hasEffort ? gOther.effort : '(no effort)'}`);

      say(`[3b] selectSession -> ritorno a "${HOME}"`);
      await b.send('selectSession', { name: HOME });
      const gBack = await b.send('readGear');
      check('dopo il ritorno la marcia coincide con la partenza',
        gBack.model === start.model && gBack.effort === start.effort,
        `${gBack.model} / ${gBack.effort}`);
    } else {
      say('[3] selectSession saltato: ' + (HOME ? 'nessuna seconda sessione in sidebar' : 'titolo attivo non fornito'));
    }

    // 4. setModel andata e ritorno
    say('');
    const target = start.model.startsWith('Sonnet') ? 'Opus 4.8' : 'Sonnet 5';
    say(`[4] setModel ${start.model} -> ${target}`);
    const m1 = await b.send('setModel', { model: target });
    check(`il pulsante ora legge ${target}`, m1.model === target, m1.model);

    say(`[4b] setModel ritorno -> ${start.model}`);
    const m2 = await b.send('setModel', { model: start.model });
    check(`il pulsante ora legge ${start.model}`, m2.model === start.model, m2.model);

    // 5. setEffort andata e ritorno. Tre casi, tenuti distinti da `hasControl`
    // (come in map.js), perche' "startLevel null" da solo li confonde:
    //   - scala letta            -> si collauda setEffort;
    //   - nessun controllo (Haiku, hasControl:false) -> salto legittimo, ma il
    //     collaudo NON prova setEffort -> lo dice il verdetto finale;
    //   - controllo presente ma scala non letta (hasControl:true) -> e' un
    //     GUASTO, non un salto: senza questo ramo il test taceva e diceva PASSATO.
    if (startLevel !== null) {
      say('');
      const tmp = startLevel === startRange.min ? startLevel + 1 : startLevel - 1;
      say(`[5] setEffort ${startLevel} -> ${tmp}`);
      const e1 = await b.send('setEffort', { level: tmp });
      check('l\'etichetta e\' cambiata', e1.effort !== start.effort, e1.effort);

      say(`[5b] setEffort ritorno -> ${startLevel}`);
      const e2 = await b.send('setEffort', { level: startLevel });
      check(`l'etichetta e' tornata "${start.effort}"`, e2.effort === start.effort, e2.effort);
      effortTested = true;
    } else if (startRange.hasControl) {
      check('scala effort leggibile su un modello che ha lo splitter', false,
        startRange.reason || 'effortRange non disponibile');
    } else {
      say('[5] setEffort NON collaudato: il modello di partenza (es. Haiku) non ha lo splitter');
    }
  } finally {
    // 6. verifica finale indipendente dai passi sopra
    say('');
    const end = await b.send('readGear');
    const ok = end.model === start.model && (!start.hasEffort || end.effort === start.effort);
    check('stato finale = stato di partenza', ok,
      `${end.model} / ${end.hasEffort ? end.effort : '(no effort)'}`);
    if (!ok) say(`RIPRISTINA A MANO: modello ${start.model}, effort ${start.effort}`);
    b.stop();
  }

  say('');
  if (failures > 0) {
    say(`ESITO: ${failures} VERIFICHE FALLITE`);
  } else if (effortTested) {
    say('ESITO: M1 PASSATO');
  } else {
    // Verde onesto: nessuna verifica fallita, ma setEffort non e' stato provato
    // (modello di partenza senza splitter). Un PASSATO liscio qui direbbe il
    // falso -- non prova che setEffort funzioni. Ripetere con un modello che ha
    // le marce (vedi intestazione) per collaudarlo.
    say('ESITO: M1 PASSATO SENZA EFFORT (setEffort non collaudato: modello di partenza senza splitter)');
  }
  REPORT.flush();
  process.exit(failures === 0 ? 0 : 1);
})().catch(err => {
  say('');
  say(`ERRORE: ${err.message}`);
  REPORT.flush();
  process.exit(1);
});
