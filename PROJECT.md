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
| **Collaudo M1 end-to-end (`test.js`)** | ✅ Riscritto e passato 7/7 sull'app viva (sessione 7): selectSession + setModel + setEffort con verifica e auto-ripristino |
| Riaggancio automatico se l'app si chiude/riapre | ✅ Rilevamento provato su morte reale (`alivecheck.ps1`), riaggancio 3/3 (`reattach.js`) |
| Scelta della finestra giusta fra le più di Claude | ✅ Si aggancia solo dove il pulsante del modello esiste |
| **Comandi malformati non fanno danni** | ✅ Provato (sessione 10) — un argomento mancante viene **rifiutato**, non interpretato: prima `setModel` senza nome innestava Fable 5 e `setEffort` senza livello scendeva al minimo, entrambi rispondendo `ok` |
| L'attuazione non ruba il puntatore | ✅ Il mouse serve per il sottomenu, ma viene rimesso dov'era (misurato: scarto 0 px) |
| Spec di build | ✅ [SPEC.md](SPEC.md) (⚠️ §2 e §4.1 superati dalla sessione 5: vedi §3 qui) |
| Prototipo UIA | ✅ [`prototype/`](prototype/) (`uia_shifter.ps1`, `uia_effort_slider.ps1`) |
| GUI (frontend) | ⬜ In carico all'altro collaboratore |

---

## 10. Da fare

Due elenchi con statuto diverso: il primo è lavoro concordato e definito, il
secondo sono idee raccolte che nessuno ha ancora progettato.

### Prossima azione — backend

I due pezzi mancanti (comando `capabilities`, riaggancio automatico) sono
**scritti, provati e chiusi**. Anche i due difetti di `map.js` rinviati in
sessione 8 sono stati chiusi in sessione 9: `probeEffort` è protetto come
`setModel` (un suo errore costa un modello, non l'intera run) e lo script esce
**3** quando dichiara la mappa incompleta, invece di 0. La coda di lavoro
concordato sul backend è vuota.

Il controllo generale della sessione 10 ha chiuso quattro difetti che i collaudi
non vedevano perché nessuno di essi mandava comandi malformati: `setModel` senza
nome innestava Fable 5 e `setEffort` senza livello scendeva al minimo, **entrambi
rispondendo `ok`**. Conseguenza per il frontend: il broker ora **rifiuta**
l'argomento mancante invece di indovinarlo, quindi una chiamata a cui la GUI ha
dimenticato un campo torna come errore e non come marcia cambiata a tradimento.

Una cosa sola resta scoperta, e va detta invece che nascosta: **le due metà del
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
