# MODEL AND FURIOUS — Direzione e obiettivo

> ⚠️ **A FINE SESSIONE È OBBLIGATORIO** chiedere all'utente se procedere con
> l'aggiornamento di questo file e di [STORICO.md](STORICO.md). Non aggiornare
> senza conferma, ma **non chiudere la sessione senza aver chiesto.**

> 📐 Specifica di build pronta allo sviluppo: **[SPEC.md](SPEC.md)** (autorevole
> sul "cosa/come"). Questo file dice *dove si va e perché*.

---

## 1. Cos'è

Un **cambio di marce fisico-simulato** per Claude, realizzato come **software
desktop autonomo** (pattern claudeine: un'app nativa che parla con Claude ma è
indipendente dalla sua interfaccia). L'utente innesta una marcia sulla leva e in
realtà cambia il modello/effort di una conversazione **dentro l'app Claude
Desktop** (quella bianca che si apre cliccando il logo), scelta da un menu a
tendina. **L'utente agisce solo sulla nostra leva: non apre mai il menu modello
dell'app a mano.**

## 2. Obiettivo

Una **GUI desktop autonoma** che pilota l'app **Claude Desktop** viva, con:

- **una sola leva-cambio** + un **menu a tendina** per scegliere la conversazione
  su cui agire (una leva, molte conversazioni);
- **leva principale** → il modello, **splitter** → l'effort;
- un **cruscotto** che legge la telemetria reale (context %, plan %).

Criterio di successo: cambiare marcia **guardando la strada** e **sapendo su quale
conversazione si agisce** prima di agire.

## 3. La meccanica reale (verificata dal vivo il 2026-07-20)

Il bersaglio è l'**app Claude Desktop** (MSIX, Electron). Si pilota via **Windows
UI Automation (UIA)**, non da terminale. Verificato sul campo (aggiornato dalla
sessione 5, che ha corretto diverse voci date per scontate prima):

| Elemento | Come appare in UIA | Azione |
|---|---|---|
| Modello corrente | `Button 'Opus 4.8'` | leggere l'etichetta |
| Menu modello | 4 `RadioButton` + sottomenu **`Altri modelli`** con altri 3 | hover sul sottomenu, poi `Select` |
| Effort corrente | `Button 'Impegno: Alto'` — **l'interfaccia è localizzata** | leggere l'etichetta |
| Effort | popup con uno **Slider**, corsa variabile per modello | `RangeValue.SetValue` |
| Sessioni (tendina) | `Button '<stato> <titolo>'` + compagno `Altre opzioni per <titolo>` | `Invoke` sulla riga |
| Telemetria | `Button 'Usage: context 6%, plan 32%'` — **oppure** `context 127.5k` (token assoluti): il formato oscilla, visti entrambi (resta in inglese) | parse di entrambi i formati |

**Vincolo chiave:** modello ed effort valgono sulla **conversazione attiva**. Per
cambiare marcia a una sessione bisogna **prima selezionarla** nella sidebar (che la
porta in primo piano nell'app), poi agire sulle leve.

**Vincolo scoperto in sessione 5 — niente input sintetico.** Il broker non deve
mai inviare tasti alla finestra Claude: `Esc` annulla il turno in corso, e
pilotare l'app da un processo che gira dentro la stessa app significa abbattersi
da soli. I popup si chiudono con `ExpandCollapsePattern.Collapse()`.

### 3.1 La mappa del cambio (letta dal vivo, non scritta a mano)

| Modello | Marce dello splitter |
|---|---|
| Fable 5 · Opus 4.8 · Opus 4.7 · Sonnet 5 | 6 — Basso, Medio, Alto, Extra, Max, Ultracode |
| Opus 4.6 · Sonnet 4.6 | 4 — Basso, Medio, Alto, **Max** (salta Extra) |
| Haiku 4.5 | nessuna — non ha controllo effort |

La corsa del cursore **si accorcia davvero** sui modelli ridotti (`0-3` invece di
`0-5`): le marce in più non restano disabilitate, spariscono. Quindi la GUI può
ricavare la lunghezza della griglia dall'app invece di conoscerla in anticipo —
ed è così che deve funzionare (§4.1).

## 4. Architettura decisa — e la correzione di rotta

**Software desktop autonomo + attuazione via UI Automation sull'app Claude
Desktop.** Provato sul campo il 2026-07-20.

- **Enumerazione** (tendina): le righe di sessione della sidebar, identificate dal
  pulsante compagno `Altre opzioni per <titolo>`.
- **Lettura** marcia/effort/telemetria: etichette dei `Button` UIA.
- **Attuazione**: modello = espandi il button → `Select` sul `RadioButton`; effort =
  espandi → `RangeValue.SetValue` sullo Slider. Verifica sempre rileggendo
  l'etichetta.

### 4.1 Principio: il backend rileva, non dichiara

Il broker **non contiene liste di modelli o di livelli di effort**. Le legge
dall'app a ogni richiesta e le passa alla GUI, che ci disegna sopra la griglia.
Motivo: una lista scritta a mano diventa falsa al primo aggiornamento di Claude, e
il fallimento sarebbe silenzioso. Conseguenza per il frontend: **la leva non può
avere una griglia fissa** — deve ridisegnarsi in base al modello scelto, e gestire
il caso Haiku dove lo splitter sparisce del tutto.

Stesso principio sugli agganci agli elementi: tabella di etichette per 10 lingue
(inglese primario) **più** un riconoscimento per forma che regge quando la lingua
non è in tabella. Le traduzioni non-italiane non sono verificabili su questa
macchina, quindi non possono essere l'unica difesa.

### Perché non le altre / cosa è stato ribaltato

| Alternativa | Esito |
|---|---|
| **Attuatore da terminale (console injection)** | **RIBALTATO.** Provato e funzionante, ma sul bersaglio SBAGLIATO (Claude Code CLI nel terminale). Il bersaglio è l'app Claude Desktop. Materiale archiviato. |
| API/canale di controllo supportato | Non documentato per cambiare modello/effort a caldo. Si pilota la GUI. |
| Estensione web / iniezione nel renderer dell'app | Scartato: fragile / bersaglio sbagliato. |
| Una leva per ogni sessione | Scartato: caos. Una leva + tendina. |

## 5. Il cruscotto

Il button `Usage: context X%, plan Y%` dà già context % (FUEL) e uso del piano via
UIA. Eventuale telemetria extra dai transcript locali (stile claudeine). Zero rete.

## 6. Il costo del cambio a caldo

Cambiare modello a metà conversazione costa (rilettura contesto a prezzo pieno). Da
verificare se l'app Claude Desktop mostra un avviso nativo allo switch e se
convenga anticiparlo nella nostra GUI.

## 7. Principio non negoziabile

> **Il bersaglio (la conversazione) è sempre visibile prima dello shift, mai
> dedotto dopo. Nessuno shift è "riuscito" senza conferma riletta dall'etichetta.**

Nota onesta: sull'app Claude Desktop, selezionare la sessione la porta in primo
piano — l'UX va costruita su questa verità, non nasconderla.

## 8. Non-obiettivi / fuori scope v1

- Nessun broadcast, nessuna marcia automatica.
- Nessun targeting implicito oltre alla selezione esplicita in tendina.
- Non è console injection nel terminale (bersaglio sbagliato, ribaltato).
- macOS/Linux, web, IDE: fuori scope.

## 9. Stato attuale

| Area | Stato |
|---|---|
| Bersaglio corretto individuato (app Claude Desktop MSIX) | ✅ |
| Enumerazione conversazioni (UIA sidebar) | ✅ Provata |
| Lettura modello/effort/telemetria (UIA) | ✅ Provata — il contatore Usage ha **due formati** (%, token) e il broker li legge entrambi (sessione 7) |
| Switch modello (UIA Select) | ✅ Provato su tutti e 7 i modelli, con ripristino verificato — ⚠️ il sottomenu "Altri modelli" ogni tanto non si apre (vedi §10) |
| Switch effort (UIA Slider) | ✅ Provato su tutte le posizioni, con ripristino verificato |
| **Ladder effort completo** | ✅ **Mappato dal vivo** — vedi §3.1, salvato in `backend/gearbox.json`. Rimisurato in sessione 8: identico, timestamp a parte. `map.js` non sovrascrive il file se la mappa è monca, e in quel caso esce 3 |
| Attuazione **senza rubare il focus** | 🟡 Letture focus-free ✅; gli switch alzano comunque l'app ⚠️ |
| **UIA Broker (M1)** | ✅ [`backend/`](backend/) — demone NDJSON, 10 comandi + diagnostici |
| Comando unico `capabilities` per la GUI | ✅ Provato sull'app viva (5,8–13 s per risposta completa, a seconda del risveglio dell'albero) |
| **Collaudo M1 end-to-end (`test.js`)** | ✅ Sessione 12 — non dichiara più "PASSATO" saltando l'effort: i tre casi (scala letta / assente / non letta) ora sono distinti con `hasControl`, e un verde senza effort si chiama "M1 PASSATO SENZA EFFORT". Rilanciato dal vivo (Opus 4.8: PASSATO; Haiku: SENZA EFFORT) |
| **`selectSession` conferma il bersaglio** | ✅ Sessione 12 — risponde `{title}` invece di `null` (principio §7), e non riversa più la sua hashtable su stdout in mezzo all'NDJSON. Verificato sul broker grezzo: 0 righe non-JSON |
| **Guasti che si distinguono dagli stati normali** | ✅ Sessione 11 — `capabilities` non può più dire "0 marce" in silenzio: una lettura mancata finisce in `errors`, e `hasControl` distingue "modello senza scala" da "scala non letta" |
| **Nessuna richiesta resta appesa** | ✅ Sessione 11 — scadenza per singola richiesta, rifiuto immediato se il broker è morto, e la sua morte non si porta più dietro il processo chiamante |
| Riaggancio automatico se l'app si chiude/riapre | ✅ Rilevamento provato su morte reale (`alivecheck.ps1`), riaggancio 3/3 (`reattach.js`) |
| Scelta della finestra giusta fra le più di Claude | ✅ Si aggancia solo dove il pulsante del modello esiste |
| **Comandi malformati non fanno danni** | ✅ Provato (sessione 10) — un argomento mancante viene **rifiutato**, non interpretato: prima `setModel` senza nome innestava Fable 5 e `setEffort` senza livello scendeva al minimo, entrambi rispondendo `ok` |
| L'attuazione non ruba il puntatore | ✅ Il mouse serve per il sottomenu, ma viene rimesso dov'era (misurato: scarto 0 px) |
| Spec di build | ✅ [SPEC.md](SPEC.md) (⚠️ §2 e §4.1 superati dalla sessione 5: vedi §3 qui) |
| Prototipo UIA | ✅ [`prototype/`](prototype/) (`uia_shifter.ps1`, `uia_effort_slider.ps1`) |
| GUI (frontend) | ⬜ In carico all'altro collaboratore — **via libera a partire** dalla leva + cruscotto sulla conversazione attiva (sessione 11, §10) |

---

## 10. Da fare

Due elenchi con statuto diverso: il primo è lavoro concordato e definito, il
secondo sono idee raccolte che nessuno ha ancora progettato.

### Prossima azione — backend

I due pezzi mancanti (comando `capabilities`, riaggancio automatico) sono
**scritti, provati e chiusi**. Anche i due difetti di `map.js` rinviati in
sessione 8 sono stati chiusi in sessione 9: `probeEffort` è protetto come
`setModel` (un suo errore costa un modello, non l'intera run) e lo script esce
**3** quando dichiara la mappa incompleta, invece di 0.

Il controllo generale della sessione 10 ha chiuso quattro difetti che i collaudi
non vedevano perché nessuno di essi mandava comandi malformati: `setModel` senza
nome innestava Fable 5 e `setEffort` senza livello scendeva al minimo, **entrambi
rispondendo `ok`**. Conseguenza per il frontend: il broker ora **rifiuta**
l'argomento mancante invece di indovinarlo, quindi una chiamata a cui la GUI ha
dimenticato un campo torna come errore e non come marcia cambiata a tradimento.

La sessione 11 ha collaudato tutto il backend per rispondere a una domanda sola
— si può cominciare il frontend? — e ha chiuso i due difetti che lo impedivano.
Nessuno dei due era un errore dimenticato: **`capabilities` dichiarava "0 marce"
su un modello che ne ha 6** perché la lettura fallita non lancia un'eccezione ma
risponde educatamente `available: false`, e viaggiava così sulla strada buona con
la lista errori vuota; e **una richiesta spedita a un broker morto non tornava
mai**, perché non falliva niente, passava solo del tempo. Ora la prima finisce in
`errors` e la seconda ha una scadenza.

La sessione 12 ha chiuso i **due difetti che restavano aperti**, entrambi sul
lato sessione, e li ha collaudati dal vivo:

1. `selectSession` rispondeva `null` e riversava la sua hashtable su stdout in
   mezzo all'NDJSON, perché il dispatch la chiamava senza catturarne il risultato.
   Chiuso: cattura il risultato e risponde `{title}`, così il bersaglio si
   conferma (§7). Verificato sul broker grezzo — stdout è solo protocollo, 0
   righe non-JSON.
2. `test.js` dichiarava "M1 PASSATO" anche saltando l'effort, per la stessa
   confusione fra "modello senza scala" e "scala non letta" già chiusa in `map.js`
   con `hasControl`. Chiuso: i tre casi sono ora distinti, e un verde senza effort
   si chiama "M1 PASSATO SENZA EFFORT". Provato su Opus 4.8 (PASSATO, effort
   collaudato) e su Haiku 4.5 (SENZA EFFORT, skip onesto).

**Nessun difetto backend/sessione resta aperto** — via del tutto libera al
frontend.

### Cosa può fare il frontend, adesso

**Si parte dalla leva e dal cruscotto sulla conversazione attiva, non dalla
tendina.** `capabilities` è una chiamata sola, provata e stabile, e copre già le
due forme che la leva deve prendere: modello a 6 marce, e Haiku che lo splitter
non ce l'ha (`gears: 0`, `hasEffort: false`). Ci sono anche gli eventi
`attached`/`reattached`/`detached`, quindi la GUI sa se l'app sparisce senza
doverlo chiedere di continuo.

Tre vincoli da progettare, non da aggirare:

- **È lento.** `capabilities` 6–15 s, `setModel` 2,5–7,6 s. Siccome la griglia va
  richiesta di nuovo dopo ogni cambio modello, un cambio marcia completo occupa
  la leva **9–20 secondi**: serve uno stato "sto innestando" onesto. E la scadenza
  per richiesta **non annulla** il lavoro del broker, smette solo di aspettarlo.
- **Un `setModel` fallito non prova che il modello non esista** (bug del
  sottomenu, §10 più sotto): la GUI deve poter riprovare.
- **`gears: 0` da solo non vuol dire "niente marce":** guardare
  `effortRange.hasControl`, oppure `errors`.

La tendina è più vicina: da sessione 12 `selectSession` **dice cosa ha fatto**
(risponde `{title}`), e `enumerate` ha visto **due** conversazioni, quindi il
giro completo andata/ritorno è stato eseguito davvero (in sessione 11 se ne
vedeva una sola). Resta però il vincolo che `enumerate` legge solo le righe che
la sidebar sta disegnando in quel momento, e la verifica *forte* del bersaglio è
ancora da progettare (vedi i due rischi rimandati qui sotto).

Una cosa resta scoperta, e va detta invece che nascosta: **le due metà del
riaggancio sono provate separatamente, non insieme.** Il rilevamento della morte
è verificato su un processo ucciso per davvero (`alivecheck.ps1`), il riaggancio
su una perdita simulata sull'app vera (`reattach.js`); la giuntura fra i due non
è osservabile perché richiederebbe di chiudere l'app che ospita chi collauda.
È il massimo ottenibile su questa macchina — chi in futuro pilotasse il broker
da fuori Claude può chiudere il cerchio con `detachtest.js`.

Due rischi noti sono stati **rimandati apposta** in sessione 7 (prematuri
finché la GUI non esiste): la verifica forte di `selectSession` (serve un
segnale affidabile di "conversazione attiva" da progettare) e il match dei
titoli per suffisso in `SessionEntries` (un titolo che è suffisso di un altro
può agganciare la riga sbagliata). Da riprendere all'integrazione col frontend.

**Un bug aperto senza causa nota (sessione 8): il sottomenu "Altri modelli" ogni
tanto non si apre.** Quando succede, i tre modelli che ci stanno dietro (Opus
4.7, Opus 4.6, Sonnet 4.6) diventano irraggiungibili e `setModel` fallisce con
"Model option not found". Nel log si riconosce da `4 -> 0`: dopo l'`Expand()` il
menu intero sparisce invece di espandersi, e hover e click trovano un elemento
senza punto cliccabile. Non è riproducibile a comando — visto fallire una volta
in una sequenza lunga, e funzionare 4 volte su 4 in prove isolate, compreso un
repro mirato che scagionava Haiku. Conseguenza per il frontend: **un `setModel`
che fallisce non significa che il modello non esista**, e la GUI deve poter
riprovare invece di dedurre che l'app non lo offre più.

### Idee raccolte — frontend / GUI

Voci aperte, non decisioni prese.

- **Cruscotto dei consumi.** Grafica che mostra la percentuale di contesto e i
  token consumati dalla chat, più eventuali altri dati disponibili. La sorgente
  esiste già ed è leggibile: il `Button 'Usage: context X%, plan Y%'`, esposto dal
  broker con `readUsage`.
- **Cambio giocattolo per Haiku.** Quando è innestato Haiku 4.5, la leva cambia
  aspetto e diventa un cambio giocattolo da bambini — ironia sul fatto che sia il
  modello meno potente. Si sposa bene con un vincolo tecnico reale: Haiku **non ha
  affatto lo splitter** (§3.1), quindi la GUI deve comunque cambiare forma in quel
  caso. L'ironia trasforma un vincolo in una battuta invece di nasconderlo.

---

> ⚠️ **PROMEMORIA FINALE — TASSATIVO**
> Prima di chiudere la sessione, chiedere all'utente:
> **"Aggiorno PROJECT.md e STORICO.md con quanto fatto oggi?"**
> Attendere conferma esplicita. Non aggiornare d'iniziativa, non saltare la domanda.
