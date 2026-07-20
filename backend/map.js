#!/usr/bin/env node
'use strict';
// Map the gearbox: for every model the app offers, how many effort detents it
// has and what each one is called.
//
// THIS CHANGES THINGS. It switches model and sweeps the effort slider on the
// conversation currently open in Claude Desktop, then puts both back. The
// original model and effort are captured first and restored in a finally block
// so an error partway through still leaves the app as it was found.
//
// Output goes to map-report.txt and gearbox.json, not to the console.
//
// gearbox.json is written ONLY when every enabled model was actually measured.
// A run that lost even one model writes gearbox-partial.json instead and leaves
// the good map untouched. Motivo: la mappa non e' un log, e' l'unica misura
// completa che esista; una serata sfortunata al menu non deve poterla cancellare
// (successo davvero il 2026-07-20: tre modelli persi dietro il submenu hanno
// sovrascritto le scale di effort di quattro). Fondere il vecchio col nuovo
// sarebbe peggio: spaccerebbe misure di ieri per misure di stasera, e "il
// backend rileva, non dichiara".
//
//   node backend/map.js
//
// Codici di uscita: 0 = mappa completa e scritta, 1 = errore fatale,
// 2 = deadline scaduta, 3 = mappa incompleta (gearbox.json non toccato).

const fs = require('fs');
const path = require('path');
const { Broker, withDeadline, makeReport } = require('./client');

const JSON_OUT = path.join(__dirname, 'gearbox.json');
const JSON_BAD = path.join(__dirname, 'gearbox-partial.json');
const REPORT   = makeReport(path.join(__dirname, 'map-report.txt'));
const say      = (...a) => REPORT.log(...a);

// Ogni modello abilitato che non e' stato misurato. Un modello senza effort NON
// entra qui: "questo modello non ha la scala" e' una misura riuscita, non un
// buco. La differenza arriva dal broker come `hasControl`, non dal testo di
// `reason` -- vedi Op-EffortRange.
const missed = [];

(async () => {
  withDeadline(900, REPORT, 'mappatura');
  const b = new Broker({ onLog: l => say(l) });
  await b.start();

  const start = await b.send('readGear');
  say(`Stato iniziale: modello=${start.model} effort=${start.hasEffort ? start.effort : '(assente)'}`);

  const startRange = start.hasEffort ? await b.send('effortRange') : { available: false };
  const startLevel = startRange.available ? startRange.current : null;
  say(`Cursore iniziale: ${startLevel === null ? '(nessuno)' : startLevel}`);
  say('');

  const models = await b.listModels();
  say(`Modelli offerti dall'app (${models.length}):`);
  models.forEach(m => say(`  ${m.label}${m.enabled ? '' : '  [disabilitato]'}${m.selected ? '  <- attivo' : ''}`));
  say('');

  const result = { probedAt: new Date().toISOString(), models: [] };

  try {
    for (const m of models) {
      if (!m.enabled) {
        say(`--- ${m.label}: disabilitato, salto ---`);
        result.models.push({ model: m.label, enabled: false });
        continue;
      }

      say(`--- ${m.label} ---`);
      let applied;
      try {
        applied = (await b.send('setModel', { model: m.label })).model;
      } catch (e) {
        say(`  cambio modello FALLITO: ${e.message}`);
        result.models.push({ model: m.label, enabled: true, error: e.message });
        missed.push(`${m.label}: ${e.message}`);
        continue;
      }
      say(`  modello attivo: ${applied}`);

      // Protetto come setModel qui sopra: un probeEffort che esplode e' un
      // modello perso, non una run persa. Senza questo catch l'errore risaliva
      // fino al finally, e la mappa moriva portandosi dietro anche i modelli
      // gia' misurati bene.
      let probe;
      try {
        probe = await b.send('probeEffort');
      } catch (e) {
        say(`  lettura effort FALLITA: ${e.message}`);
        result.models.push({ model: applied, enabled: true, error: e.message });
        missed.push(`${applied}: ${e.message}`);
        continue;
      }

      if (!probe.available) {
        // hasControl distingue le due risposte vuote: false = questo modello la
        // scala non ce l'ha (misura riuscita), true = ce l'ha ma non si e'
        // aperta (buco). Solo il secondo caso invalida la mappa.
        const buco = probe.hasControl === true;
        say(`  effort: NESSUNO (${probe.reason})${buco ? '  <- NON MISURATO' : ''}`);
        result.models.push({ model: applied, enabled: true, effort: null, reason: probe.reason });
        if (buco) missed.push(`${applied}: ${probe.reason}`);
        continue;
      }

      const levels = (probe.positions || '').split('\n').filter(Boolean).map(l => {
        const [value, label] = l.split('\t');
        return { value: Number(value), label: label || null };
      });
      const usable = levels.filter(l => l.label);
      say(`  effort: cursore ${probe.min}-${probe.max}, ${usable.length} livelli distinti leggibili`);
      levels.forEach(l => say(`    ${l.value} = ${l.label ?? '(illeggibile)'}`));
      if (!probe.restoredOk) say('  ATTENZIONE: ripristino cursore incerto');

      result.models.push({ model: applied, enabled: true, min: probe.min, max: probe.max, levels });
    }
  } finally {
    say('');
    say('--- ripristino stato iniziale ---');
    try {
      const back = await b.send('setModel', { model: start.model });
      say(`  modello: ${back.model}`);
      if (startLevel !== null) {
        const e = await b.send('setEffort', { level: startLevel });
        say(`  effort : ${e.effort}`);
      }
      const now = await b.send('readGear');
      const ok = now.model === start.model
              && (!start.hasEffort || now.effort === start.effort);
      say(`  verifica: modello=${now.model} effort=${now.hasEffort ? now.effort : '(assente)'}`);
      say(`  ${ok ? 'RIPRISTINATO come era' : 'DIVERSO DA COME ERA - controlla a mano'}`);
    } catch (e) {
      say(`  RIPRISTINO FALLITO: ${e.message}`);
      say(`  rimetti a mano: modello ${start.model}, effort ${start.effort}`);
    }
    b.stop();
  }

  say('');
  if (missed.length === 0) {
    fs.writeFileSync(JSON_OUT, JSON.stringify(result, null, 2), 'utf8');
    say(`Mappa completa: ${result.models.length} modelli. Salvata in ${JSON_OUT}`);
  } else {
    // Il parziale si scrive lo stesso: serve a capire cosa e' mancato, e tenerlo
    // fuori da gearbox.json e' proprio il punto.
    result.incomplete = missed;
    fs.writeFileSync(JSON_BAD, JSON.stringify(result, null, 2), 'utf8');
    say(`MAPPA INCOMPLETA: ${missed.length} modelli su ${result.models.length} non misurati.`);
    missed.forEach(m => say(`  ! ${m}`));
    say(`${JSON_OUT} NON e' stato toccato: la mappa buona precedente e' intatta.`);
    say(`Il risultato parziale e' in ${JSON_BAD}. Rilancia quando il menu collabora.`);
    // Una mappa monca non e' un successo: chi lancia lo script deve poterlo
    // sapere senza leggere il report. exitCode invece di process.exit() cosi'
    // il flush qui sotto e la chiusura del broker avvengono comunque.
    process.exitCode = 3;
  }
  REPORT.flush();
})().catch(err => {
  say('');
  say(`ERRORE: ${err.message}`);
  REPORT.flush();
  process.exit(1);
});
